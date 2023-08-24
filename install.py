#!/usr/bin/env python3
#
# Copyright (c) 2019 Martin Storsjo
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
import os
import sys
import subprocess
from pathlib import Path

from .fixinclude import main as fixinclude
from .lowercase import main as lowercase


def ln_s(src, dst):
    if not dst.exists():
        dst.symlink_to(src)

def main():
    if len(sys.argv) < 2:
        print(f"{sys.argv[0]} {{vc.zip sdk.zip target|target}}")
        sys.exit(0)

    if len(sys.argv) == 3:
        vc_zip = Path(sys.argv[1]).resolve()
        sdk_zip = Path(sys.argv[2]).resolve()
        dest = Path(sys.argv[3]).resolve()
    else:
        dest = Path(sys.argv[1]).resolve()
    orig = Path(__file__).resolve().parent

    dest.mkdir(parents=True, exist_ok=True)
    os.chdir(dest)
    dest = Path.cwd()

    if "vc_zip" in locals():
        subprocess.run(["unzip", str(vc_zip)], check=True)
    ln_s("kits", dest / "Windows Kits")
    ln_s("vc", dest / "VC")
    ln_s("vc/tools", dest / "Tools")
    ln_s("vc/tools/msvc", dest / "MSVC")

    # Add symlinks like LIBCMT.lib -> libcmt.lib. These are properly lowercased
    # out of the box, but MSVC produces directives like /DEFAULTLIB:"LIBCMT"
    # /DEFAULTLIB:"OLDNAMES", which lld-link doesn't find on a case sensitive
    # filesystem. Therefore add matching case symlinks for this, to allow
    # linking MSVC built objects with lld-link.
    os.chdir((dest / "vc" / "tools" / "msvc").resolve())
    for arch in ["x86", "x64", "arm", "arm64"]:
        if not (dest / "vc" / "tools" / "msvc" / arch).is_dir():
            continue
        os.chdir((dest / "vc" / "tools" / "msvc" / arch).resolve())
        for i in ["libcmt", "libcmtd", "msvcrt", "msvcrtd", "oldnames"]:
            ln_s(f"{i}.lib", (dest / "vc" / "tools" / "msvc" / arch / f"{i.upper()}.lib").resolve())
        os.chdir("..")
    os.chdir("..")

    # Fix casing issues in the MSVC headers. These headers mostly have consistent
    # lowercase naming among themselves, but they do reference some WinSDK headers
    # with mixed case names (in a spelling that isn't present in the WinSDK).
    # Thus process them to reference the other headers with lowercase names.
    # Also lowercase these files, as a few of them do have non-lowercase names,
    # and the call to fixinclude lowercases those references.
    lowercase("include", symlink=True)
    fixinclude("include")
    os.chdir(dest / "bin")
    # vctip.exe is known to cause problems at some times; just remove it.
    # See https://bugs.chromium.org/p/chromium/issues/detail?id=735226 and
    # https://github.com/mstorsjo/msvc-wine/issues/23 for references.
    for i in subprocess.check_output(["find", ".", "-iname", "vctip.exe"]).decode().splitlines():
        os.remove(i)
    if (dest / "bin" / "HostARM64").is_dir():
        # 17.2 - 17.3
        os.rename(dest / "bin" / "HostARM64", dest / "bin" / "Hostarm64")
    if (dest / "bin" / "HostArm64").is_dir():
        # 17.4
        os.rename(dest / "bin" / "HostArm64", dest / "bin" / "Hostarm64")
    if (dest / "bin" / "Hostarm64" / "ARM64").is_dir():
        # 17.2 - 17.3
        os.rename(dest / "bin" / "Hostarm64" / "ARM64", dest / "bin" / "Hostarm64" / "arm64")
    os.chdir(dest)

    if (dest / "kits" / "10").is_dir():
        os.chdir(dest / "kits" / "10")
    else:
        (dest / "kits").mkdir(parents=True, exist_ok=True)
        os.chdir(dest / "kits")
        subprocess.run(["unzip", str(sdk_zip)], check=True)
        os.chdir("10")
    ln_s("Lib", "lib")
    ln_s("Include", "include")
    os.chdir("../..")
    sdkver = (dest / "kits" / "10" / "include" / "*").resolve().basename()
    msvcver = (dest / "vc" / "tools" / "msvc" / "*").resolve().basename()
    with (orig / "wrappers" / "msvcenv.sh").open("r") as f:
        content = f.read()
    content = content.replace(f"MSVCVER=.*", f"MSVCVER={msvcver}").replace(f"SDKVER=.*", f"SDKVER={sdkver}").replace("x64", "arm64" if os.uname().machine == "aarch64" else "x64")    
    with Path("msvcenv.sh").open("w") as f:
        f.write(content)
    for arch in ["x86", "x64", "arm", "arm64"]:
        if not (Path("vc") / "tools" / "msvc" / msvcver / "bin" / "Hostx64").isdir():
            continue
        arch_path = Path("bin") / arch
        os.makedirs(arch_path, exist_ok=True)
        subprocess.run(["cp", "-a", orig / "wrappers" / "*", arch_path], check=True)
        with (arch_path / "msvcenv.sh").open("w") as f:
            f.write(content.replace("ARCH=.*", f"ARCH={arch}"))
    os.remove("msvcenv.sh")

    if (dest / "bin" / "arm64").is_dir() and Path("/usr/bin/wine64").exists():
        subprocess.run(["WINEDEBUG=-all", "wine64", "wineboot"], check=True)
        print("Build msvctricks ...")
        subprocess.run([dest / "bin" / "arm64" / "cl", "/EHsc", "/O2", orig / "msvctricks.cpp"], check=True)
        if os.path.exists("msvctricks.exe"):
            os.rename("msvctricks.exe", Path("bin") / "msvctricks")
            os.remove("msvctricks.obj")
            print("Build msvctricks done.")
        else:
            print("Build msvctricks failed.")

if __name__ == "__main__":
    main()
#!/usr/bin/python
#
# Copyright (c) 2019 Martin Storsjo
# Copyright (c) 2022 Mathias Panzenböck
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

import re
import os
import sys
import zipfile

from typing import Optional, Match
from os.path import dirname, join as joinpath, basename, abspath, isdir, islink
from shutil import copy
from re import sub, escape as re_escape, M
from shlex import quote as sh_quote

ARCHS = 'x86', 'x64', 'arm', 'arm64'

def replace_vars(input_file: str, output_file: str, /, **vars: str) -> None:
    with open(input_file, 'r') as infp:
        s = infp.read()

    for key, val in vars.items():
        s = sub(f"^{re_escape(key)}=.*", lambda match: f"{key}={sh_quote(val)}", s, flags=M)

    with open(output_file, 'w') as outfp:
        outfp.write(s)

def make_lowercase(path: str) -> None:
    for child in os.listdir(path):
        child_path = joinpath(path, child)
        lower_child = child.lower()

        if child != lower_child:
            lower_child_path = joinpath(path, lower_child)
            os.rename(child_path, lower_child_path)
            child = lower_child
            child_path = lower_child_path

        if islink(child_path):
            target = os.readlink(child_path)
            lower_target = target.lower()
            if target != lower_target:
                os.unlink(child_path)
                os.symlink(lower_target, child_path)

        elif isdir(child_path):
            make_lowercase(child_path)

RE_INCLUDE = re.compile(rb'^(?P<prefix>\s*#\s*include\s*)(?P<include><(?:[^>]*)>|"(?:[^"\\]|\\.)*")(?P<suffix>.*)', M)

def _fix_include(match: Match[bytes]) -> bytes:
    include = match.group('include').lower().replace(b'\\', b'/')
    return match.group('prefix') + include + match.group('suffix')

def fix_include(path: str) -> None:
    for child in os.listdir(path):
        child_path = joinpath(path, child)

        if not islink(child_path):
            if isdir(child_path):
                fix_include(child_path)
            else:
                try:
                    with open(child_path, 'rb') as fin:
                        source = fin.read()

                    new_source = RE_INCLUDE.sub(_fix_include, source)

                    if source != new_source:
                        with open(child_path, 'wb') as fout:
                            fout.write(new_source)

                except Exception as error:
                    raise RuntimeError(f'{child_path}: {error}') from error

def main() -> None:
    argc = len(sys.argv)
    VC_ZIP:  Optional[str]
    SDK_ZIP: Optional[str]

    if argc == 3:
        VC_ZIP  = joinpath(abspath(dirname(sys.argv[1])), basename(sys.argv[1]))
        SDK_ZIP = joinpath(abspath(dirname(sys.argv[2])), basename(sys.argv[2]))
        DEST = sys.argv[3]
    elif argc == 2:
        DEST = sys.argv[1]
        VC_ZIP  = None
        SDK_ZIP = None
    else:
        print(f"{sys.argv[0]} {{vc.zip sdk.zip target|target}}", file=sys.stderr)
        sys.exit(1)

    ORIG = abspath(dirname(sys.argv[0]))

    os.makedirs(DEST, exist_ok=True)

    os.chdir(DEST)
    DEST = abspath(os.curdir)

    if VC_ZIP:
        with zipfile.ZipFile(VC_ZIP, 'r') as zipf:
            zipf.extractall(DEST)

    os.rename('VC', 'vc')
    os.rename('vc/Tools', 'vc/tools')
    os.rename('vc/tools/MSVC', 'vc/tools/msvc')

    # Add symlinks like LIBCMT.lib -> libcmt.lib. These are properly lowercased
    # out of the box, but MSVC produces directives like /DEFAULTLIB:"LIBCMT"
    # /DEFAULTLIB:"OLDNAMES", which lld-link doesn't find on a case sensitive
    # filesystem. Therefore add matching case symlinks for this, to allow
    # linking MSVC built objects with lld-link.
    MSVCVER = os.listdir('vc/tools/msvc')[0]
    os.chdir(f'vc/tools/msvc/{MSVCVER}/lib')
    for arch in ARCHS:
        os.chdir(arch)
        for name in 'libcmt', 'libcmtd', 'msvcrt', 'msvcrtd', 'oldnames':
            os.symlink(name + '.lib', name.upper() + '.lib')
        os.chdir('..')
    os.chdir('../bin')

    # vctip.exe is known to cause problems at some times; just remove it.
    # See https://bugs.chromium.org/p/chromium/issues/detail?id=735226 and
    # https://github.com/mstorsjo/msvc-wine/issues/23 for references.
    for dirpath, dirnames, filenames in os.walk('.'):
        for filename in filenames:
            if filename == 'vctip.exe':
                os.unlink(joinpath(dirpath, filename))

    os.chdir(DEST)

    if isdir('kits/10'):
        os.chdir('kits/10')
    elif not SDK_ZIP:
        print(f"{DEST}/kits/10 does not exist and sdk.zip was not provided", file=sys.stderr)
        print(f"{sys.argv[0]} {{vc.zip sdk.zip target|target}}", file=sys.stderr)
        sys.exit(1)
    else:
        os.mkdir('kits')
        os.chdir('kits')
        with zipfile.ZipFile(SDK_ZIP, 'r') as zipf:
            zipf.extractall('.')
        os.chdir('10')

    os.rename('Lib', 'lib')
    os.rename('Include', 'include')
    os.chdir('../..')

    SDKVER = os.listdir('kits/10/include')[0]

    make_lowercase(f"kits/10/include/{SDKVER}/um")
    make_lowercase(f"kits/10/include/{SDKVER}/shared")
    fix_include(f"kits/10/include/{SDKVER}/um")
    fix_include(f"kits/10/include/{SDKVER}/shared")

    for arch in ARCHS:
        make_lowercase(f"kits/10/lib/{SDKVER}/um/{arch}")

    replace_vars(f"{ORIG}/wrappers/msvcenv.sh", "msvcenv.sh",
        MSVCVER=MSVCVER,
        SDKVER=SDKVER)

    wrapper_dir = joinpath(ORIG, 'wrappers')
    for arch in ARCHS:
        bindir = joinpath('bin', arch)
        os.makedirs(bindir, exist_ok=True)
        for name in os.listdir(wrapper_dir):
            copy(joinpath(wrapper_dir, name), joinpath(bindir, name))
        replace_vars("msvcenv.sh", f"bin/{arch}/msvcenv.sh", ARCH=arch)

if __name__ == "__main__":
    main()

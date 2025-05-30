#!/usr/bin/env sh
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

set -e

if [ $# -lt 1 ]; then
    echo "$0 {vc.zip sdk.zip target|target}"
    exit 0
fi

if [ $# -eq 3 ]; then
    VC_ZIP=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
    SDK_ZIP=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
    DEST=$3
else
    DEST=$1
fi
ORIG=$(cd "$(dirname "$0")" && pwd)

mkdir -p "$DEST"
cd "$DEST"
DEST=$(pwd)

ln_s() {
    if [ ! -e "$2" ]; then
        ln -s "$1" "$2"
    fi
}

if [ -n "$VC_ZIP" ]; then
    unzip "$VC_ZIP"
fi
ln_s "Windows Kits" kits
ln_s VC vc
ln_s Tools vc/tools
ln_s MSVC vc/tools/msvc

# Add symlinks like LIBCMT.lib -> libcmt.lib. These are properly lowercased
# out of the box, but MSVC produces directives like /DEFAULTLIB:"LIBCMT"
# /DEFAULTLIB:"OLDNAMES", which lld-link doesn't find on a case sensitive
# filesystem. Therefore add matching case symlinks for this, to allow
# linking MSVC built objects with lld-link.
cd $(echo vc/tools/msvc/* | awk '{print $1}')/lib
for arch in x86 x64 arm arm64; do
    if [ ! -d "$arch" ]; then
        continue
    fi
    cd $arch
    for i in libcmt libcmtd msvcrt msvcrtd oldnames; do
        ln_s $i.lib $(echo $i | tr [a-z] [A-Z]).lib
    done
    cd ..
done
cd ..
# Fix casing issues in the MSVC headers. These headers mostly have consistent
# lowercase naming among themselves, but they do reference some WinSDK headers
# with mixed case names (in a spelling that isn't present in the WinSDK).
# Thus process them to reference the other headers with lowercase names.
# Also lowercase these files, as a few of them do have non-lowercase names,
# and the call to fixinclude lowercases those references.
"$ORIG"/lowercase -symlink include
"$ORIG"/fixinclude include
if [ -d "atlmfc/include" ]; then
    # The ATL headers are lowercased themselves, but they refer to
    # WinSDK headers with mixed casing.
    "$ORIG"/fixinclude "atlmfc/include"
fi
cd bin
# vctip.exe is known to cause problems at some times; just remove it.
# See https://bugs.chromium.org/p/chromium/issues/detail?id=735226 and
# https://github.com/mstorsjo/msvc-wine/issues/23 for references.
for i in $(find . -iname vctip.exe); do
    rm $i
done
if [ -d HostX64 ]; then
    # 15.x - 16.4
    mv HostX64 Hostx64
fi
if [ -d HostARM64 ]; then
    # 17.2 - 17.3
    mv HostARM64 Hostarm64
fi
if [ -d HostArm64 ]; then
    # 17.4
    mv HostArm64 Hostarm64
fi
if [ -d Hostarm64/ARM64 ]; then
    # 17.2 - 17.3
    mv Hostarm64/ARM64 Hostarm64/arm64
fi
cd "$DEST"

if [ -d kits/10 ]; then
    cd kits/10
else
    mkdir kits
    cd kits
    unzip "$SDK_ZIP"
    cd 10
fi
ln_s Lib lib
ln_s Include include
cd ../..

SDKVER=$(basename $(echo kits/10/include/10.* | awk '{print $NF}'))
echo Using SDK version $SDKVER

# Lowercase the SDK headers and libraries. As long as cl.exe is executed
# within wine, this is mostly not necessary.
#
# (Older versions of cl.exe needed it, because those versions would produce
# dependency paths with incorrect casing for some headers, breaking rebuilds
# with tools that check dependencies.)
#
# But lowercasing the headers allows using them with case sensitive native
# tools (such as clang-cl and lld-link). Leaving their original casing isn't
# an option, because the headers aren't self consistent (headers are
# included with a different mix of upper/lower case than what they have
# on disk).
#
# The original casing of file names is preserved though, by adding lowercase
# symlinks instead of doing a plain rename, so files can be referred to with
# either the out of the box filename or with the lowercase name.
for incdir in um shared winrt km; do
    SDK_INCDIR="kits/10/include/$SDKVER/$incdir"

    if [ -d "$SDK_INCDIR" ]; then
        "$ORIG"/lowercase -map_winsdk -symlink "$SDK_INCDIR"
        "$ORIG"/fixinclude -map_winsdk "$SDK_INCDIR"
    fi
done

# The WDF is a part of the Windows Driver Kit.
WDF_INCDIR="kits/10/include/wdf"
if [ -d "$WDF_INCDIR" ]; then
    "$ORIG"/lowercase -map_winsdk -symlink "$WDF_INCDIR"
    "$ORIG"/fixinclude -map_winsdk "$WDF_INCDIR"
fi

for arch in x86 x64 arm arm64; do
    SDK_LIBDIR="kits/10/lib/$SDKVER/um/$arch"
    DDK_LIBDIR="kits/10/lib/$SDKVER/km/$arch"

    if [ -d "$SDK_LIBDIR" ]; then
        "$ORIG"/lowercase -symlink "$SDK_LIBDIR"
    fi
    if [ -d "$DDK_LIBDIR" ]; then
        "$ORIG"/lowercase -symlink "$DDK_LIBDIR"
    fi
done

host=x64
# .NET-based tools use different host arch directories
dotnet_host=amd64
if [ "$(uname -m)" = "aarch64" ]; then
    host=arm64
    dotnet_host=arm64
fi

MSVCVER=$(basename $(echo vc/tools/msvc/* | awk '{print $1}'))
echo Using MSVC version $MSVCVER

# Support `import std` for CMake.
if [ -d "VC/Tools/MSVC/$MSVCVER/modules" ]; then
    ln_s VC/Tools/MSVC/$MSVCVER/modules modules
fi

cat "$ORIG"/wrappers/msvcenv.sh \
| sed 's/MSVCVER=.*/MSVCVER='$MSVCVER/ \
| sed 's/SDKVER=.*/SDKVER='$SDKVER/ \
| sed s/x64/$host/ \
| sed s/amd64/$dotnet_host/ \
> msvcenv.sh

for arch in x86 x64 arm arm64; do
    if [ ! -d "vc/tools/msvc/$MSVCVER/bin/Host$host/$arch" ]; then
        continue
    fi
    mkdir -p bin/$arch
    cp -a "$ORIG"/wrappers/* bin/$arch
    cat msvcenv.sh | sed 's/ARCH=.*/ARCH='$arch/ > bin/$arch/msvcenv.sh
done
rm msvcenv.sh

if [ -d "$DEST/bin/$host" ]; then
    if WINE="$(command -v wine64 || command -v wine)"; then
        WINEDEBUG=-all "${WINE}" wineboot &>/dev/null
        echo "Build msvctricks ..."
        "$DEST/bin/$host/cl" /EHsc /O2 "$ORIG/msvctricks.cpp"
        if [ $? -eq 0 ]; then
            mv msvctricks.exe bin/
            rm msvctricks.obj
            echo "Build msvctricks done."
        else
            echo "Build msvctricks failed."
        fi
    fi
fi

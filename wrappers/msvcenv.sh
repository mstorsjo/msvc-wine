#!/bin/bash
#
# Copyright (c) 2018 Martin Storsjo
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

SDK=kits\\10
SDK_UNIX=kits/10
BASE_UNIX=$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)
# Support having the wrappers in a directory one or two levels below the
# installation directory.
if [ ! -d "$BASE_UNIX/vc" ]; then
    BASE_UNIX=$(cd "$BASE_UNIX"/.. && pwd)
fi
BASE=z:${BASE_UNIX//\//\\}
MSVCVER=14.13.26128
SDKVER=10.0.16299.0
ARCH=x86
MSVCDIR="$BASE\\vc\\tools\\msvc\\$MSVCVER"
SDKINCLUDE="$BASE\\$SDK\\include\\$SDKVER"
SDKLIB="$BASE\\$SDK\\lib\\$SDKVER"
BINDIR=$BASE_UNIX/vc/tools/msvc/$MSVCVER/bin/Hostx64/$ARCH
SDKBINDIR=$BASE_UNIX/$SDK_UNIX/bin/$SDKVER/x64
MSBUILDBINDIR=$BASE_UNIX/MSBuild/Current/Bin/amd64
export INCLUDE="$MSVCDIR\\include;$SDKINCLUDE\\shared;$SDKINCLUDE\\ucrt;$SDKINCLUDE\\um;$SDKINCLUDE\\winrt"
export LIB="$MSVCDIR\\lib\\$ARCH;$SDKLIB\\ucrt\\$ARCH;$SDKLIB\\um\\$ARCH"
export LIBPATH="$LIB"
# "$MSVCDIR\\bin\\Hostx64\\x64" is included in PATH for DLLs.
export WINEPATH="${BINDIR//\//\\};${SDKBINDIR//\//\\};$MSVCDIR\\bin\\Hostx64\\x64"
export WINEDLLOVERRIDES="vcruntime140=n;vcruntime140_1=n"

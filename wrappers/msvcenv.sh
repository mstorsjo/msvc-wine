#!/usr/bin/env bash
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
BASE=$(winepath -w "$BASE_UNIX")
MSVCVER=14.13.26128
SDKVER=10.0.16299.0
ARCH=x86
MSVCBASE="$BASE\\vc"
MSVCBASE_UNIX=$(winepath -u "$MSVCBASE")
SDKBASE="$BASE\\$SDK"
SDKBASE_UNIX=$(winepath -u "$SDKBASE")
MSVCDIR="$MSVCBASE\\tools\\msvc\\$MSVCVER"
MSVCDIR_UNIX=$(winepath -u "$MSVCDIR")
SDKINCLUDE="$SDKBASE\\include\\$SDKVER"
SDKINCLUDE_UNIX=$(winepath -u "$SDKINCLUDE")
SDKLIB="$SDKBASE\\lib\\$SDKVER"
SDKLIB_UNIX=$(winepath -u "$SDKLIB")
BINDIR=$BASE\\vc\\tools\\msvc\\$MSVCVER\\bin\\Hostx64\\$ARCH
BINDIR_UNIX=$(winepath -u "$BINDIR")
SDKBINDIR=$BASE\\$SDK\\bin\\$SDKVER\\x64
SDKBINDIR_UNIX=$(winepath -u "$SDKBINDIR")
MSBUILDBINDIR=$BASE_UNIX/MSBuild/Current/Bin/amd64
MSBUILDBINDIR_UNIX=$(winepath -u "$MSBUILDBINDIR")
export INCLUDE="$MSVCDIR\\atlmfc\\include;$MSVCDIR\\include;$SDKINCLUDE\\shared;$SDKINCLUDE\\ucrt;$SDKINCLUDE\\um;$SDKINCLUDE\\winrt;$SDKINCLUDE\\km"
export LIB="$MSVCDIR\\atlmfc\\lib\\$ARCH;$MSVCDIR\\lib\\$ARCH;$SDKLIB\\ucrt\\$ARCH;$SDKLIB\\um\\$ARCH;$SDKLIB\\km\\$ARCH"
export LIBPATH="$LIB"
# "$MSVCDIR\\bin\\Hostx64\\x64" is included in PATH for DLLs.
export WINEPATH="${BINDIR//\//\\};${SDKBINDIR//\//\\};$MSVCDIR\\bin\\Hostx64\\x64"
export WINEDLLOVERRIDES="vcruntime140=n;vcruntime140_1=n"

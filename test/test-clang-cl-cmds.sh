#!/bin/bash
#
# Copyright (c) 2023 Martin Storsjo
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

. "${0%/*}/test.sh"

# ${BIN} set up by the caller
if [ -z "$BIN" ]; then
    echo Must set the BIN env variable pointing to the MSVC bin directory
    exit 1
fi

BASE_UNIX=$(. "${BIN}msvcenv.sh" && echo $BASE_UNIX)
TARGET_ARCH=$(. "${TESTS}../msvcenv-native.sh" && echo $TARGET_ARCH)

# Since Clang 13, it's possible to point out the installed MSVC/WinSDK with
# the /winsysroot parameter. LLD also provides the same parameter since
# version 15. (For versions 13 and 14, this parameter can still be used
# for linking, as long as linking is done via Clang.)
EXEC "" clang-cl --target=$TARGET_ARCH-windows-msvc "${TESTS}hello.c" -Fehello.exe -winsysroot "$BASE_UNIX" -fuse-ld=lld

# Set up the INCLUDE/LIB env variables for compilation without directly
# pointing at the installation.
. ${TESTS}../msvcenv-native.sh
EXEC "" clang-cl --target=$TARGET_TRIPLE "${TESTS}hello.c" -c -Fohello.obj
EXEC "" lld-link hello.obj -out:hello.exe

EXIT

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

. ${TESTS}/../msvcenv-native.sh

CMAKE_ARGS=(
    -DCMAKE_BUILD_TYPE=RelWithDebInfo
    -DCMAKE_SYSTEM_NAME=Windows
    -DCMAKE_MT=$(which llvm-mt)
)

EXEC "" CC="clang-cl --target=$TARGET_TRIPLE" CXX="clang-cl --target=$TARGET_TRIPLE" RC="llvm-rc" cmake -S"$TESTS" -GNinja "${CMAKE_ARGS[@]}"
EXEC "" ninja -v

# Rerun ninja to make sure that dependencies aren't broken.
EXEC ninja-rerun ninja -d explain -v
DIFF ninja-rerun.err - <<EOF
EOF
DIFF ninja-rerun.out - <<EOF
ninja: no work to do.
EOF


EXIT

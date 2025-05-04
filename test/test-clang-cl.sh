#!/usr/bin/env bash
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

cd "$TESTS"

for arch in x86 x64 arm arm64; do
    BIN="${1:-/opt/msvc}/bin/$arch/"
    if [ ! -d "$BIN" ]; then
        continue
    fi
    # Windows SDK 10.0.26100.0 no long targets Arm32.
    if [ "$arch" = "arm" ] && printf "%s\n" 10.0.26100.0 $(. "${BIN}msvcenv.sh" && echo "$SDKVER") | sort -VC; then
        continue
    fi

    EXEC "" BIN=$BIN ./test-clang-cl-cmds.sh
    EXEC "" BIN=$BIN ./test-cmake-clang-cl.sh
done

EXIT

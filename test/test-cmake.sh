#!/bin/bash
#
# Copyright (c) 2023 Huang Qinjin
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


MSVCDIR=$(. "${BIN}msvcenv.sh" && echo $MSVCDIR)
MSVCDIR=${MSVCDIR//\\//}
MSVCDIR=${MSVCDIR#z:}

CMAKE_ARGS=(
    -DMSVCDIR="$MSVCDIR"
    -DCMAKE_BUILD_TYPE=RelWithDebInfo
    -DCMAKE_SYSTEM_NAME=Windows
)

case $OSTYPE in
    darwin*)
        CMAKE_ARGS+=(
            # mt.exe always crashes on macOS.
            -DCMAKE_EXE_LINKER_FLAGS=/MANIFEST:NO
            -DCMAKE_SHARED_LINKER_FLAGS=/MANIFEST:NO
            # No winbind package available on macOS.
            # https://github.com/mstorsjo/msvc-wine/issues/6
            -DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT=Embedded
        ) ;;
esac

EXEC "" CC=${BIN}cl CXX=${BIN}cl RC=${BIN}rc cmake -S"$TESTS" -GNinja "${CMAKE_ARGS[@]}"
EXEC "" ninja -v

# Rerun ninja to make sure that dependencies aren't broken.
EXEC ninja-rerun ninja -d explain -v
DIFF ninja-rerun.err - <<EOF
EOF
DIFF ninja-rerun.out - <<EOF
ninja: no work to do.
EOF


EXIT

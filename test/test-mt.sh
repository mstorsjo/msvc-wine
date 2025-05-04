#!/usr/bin/env bash
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


# https://gitlab.kitware.com/cmake/cmake/-/blob/v3.26.0/Source/cmcmd.cxx#L2405
# https://github.com/mstorsjo/msvc-wine/pull/63
mtRetIsUpdate() {
    eval $(printf '%q ' "$@")
    local mtRet=$?
    if [ $mtRet -eq 1090650113 ] || [ $mtRet -eq 187 ]; then
        return 0
    else
        return 1
    fi
}

EXEC "" mtRetIsUpdate ${BIN}mt /nologo /manifest ${TESTS}utf8.manifest /out:output.manifest /notify_update
EXEC ""               ${BIN}mt /nologo /manifest ${TESTS}utf8.manifest /out:output.manifest /notify_update


EXIT

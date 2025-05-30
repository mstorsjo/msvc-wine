#!/usr/bin/env bash
#
# Copyright (c) 2024 Sergey Kvachonok
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

for config in Debug Release; do
    for useenv in true false; do
        # Trailing slash is required in MSBuild directory properties.
        OUTDIR="Z:${CWD}useenv-${useenv}/${config}/"

        EXEC "" ${BIN}msbuild \
          /p:UseEnv=${useenv} /p:Configuration=${config} \
          /p:IntDir="${OUTDIR}" /p:OutDir="${OUTDIR}" \
          "${TESTS}HelloWorld.vcxproj"
    done
done

EXIT

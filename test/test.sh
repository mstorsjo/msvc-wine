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

[ "$0" != "$BASH_SOURCE" ] && sourced=1 || sourced=0
TESTS=$(cd "$(dirname "$BASH_SOURCE")" && pwd)/
NAME=$(basename "$0")

num_of_tests=0
num_of_fails=0

EXEC() {
    local output=$1
    if [ -n "$output" ]; then
        local stdout="$output.out"
        local stderr="$output.err"
        shift
        local cmd=$(printf '%q ' "$@")
        eval "$cmd" >$stdout 2>$stderr
    else
        shift
        local cmd=$(printf '%q ' "$@")
        echo EXEC: "$cmd"
        eval "$cmd"
    fi

    local ec=$?
    num_of_tests=$(($num_of_tests+1))
    if [ $ec -ne 0 ]; then
        num_of_fails=$(($num_of_fails+1))
        if [ -n "$output" ]; then
            echo EXEC: "$cmd"
            cat $stdout
            cat $stderr 1>&2
            rm -f "$stdout" "$stderr"
        fi
    fi
    return $ec
}

DIFF() {
    git --no-pager diff --no-index -R "$@"
    local ec=$?
    num_of_tests=$(($num_of_tests+1))
    if [ $ec -ne 0 ]; then
        num_of_fails=$(($num_of_fails+1))
    fi
    return $ec
}

EXIT() {
    printf "EXIT: %-16s  total tests: %-3d  failed tests: %-3d" $NAME $num_of_tests $num_of_fails
    if [ $num_of_fails -gt 0 ]; then
        printf " ............. Failed\n"
        exit 1
    else
        printf " ............. Passed\n"
        exit 0
    fi
}

if [ $sourced -eq 1 ]; then
    CWD=$(mktemp -d -t msvc-wine.tmp.XXXX)/
    if [ $? -ne 0 ]; then
        exit 1
    else
        trap "rm -r '$CWD'" EXIT
        cd "$CWD"
        return 0
    fi
else
    CWD="$TESTS"
    cd "$CWD"
fi

for arch in x86 x64 arm arm64; do
    BIN="${1:-/opt/msvc}/bin/$arch/"
    if [ ! -d "$BIN" ]; then
        continue
    fi

    EXEC "" BIN=$BIN ./test-cl.sh
    EXEC "" BIN=$BIN ./test-mt.sh
    EXEC "" BIN=$BIN ./test-dumpbin.sh
    EXEC "" BIN=$BIN ./test-asm.sh
    EXEC "" BIN=$BIN ./test-midl.sh
    EXEC "" BIN=$BIN ./test-cmake.sh
    EXEC "" BIN=$BIN ./test-meson.sh
done

EXIT

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


ARCH=$(. "${BIN}msvcenv.sh" && echo $ARCH)

case $ARCH in
x86)
    CPU_FAMILY=x86
    CPU=i686
    ;;
x64)
    CPU_FAMILY=x86_64
    CPU=x86_64
    ;;
arm)
    CPU_FAMILY=arm
    CPU=armv7
    ;;
arm64)
    CPU_FAMILY=aarch64
    CPU=aarch64
    ;;
esac

cat >cross.txt <<EOF
[binaries]
c = 'cl'
cpp = 'cl'
ar = 'lib'
windres = 'rc'
;exe_wrapper = ['wine']

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'windows'
cpu_family = '$CPU_FAMILY'
cpu = '$CPU'
endian = 'little'
EOF

MESON_ARGS=(
    --buildtype debugoptimized
    --cross-file cross.txt
)

export PATH="$BIN:$PATH"

EXEC "" meson setup "$TESTS" "${MESON_ARGS[@]}"
EXEC "" ninja -v

# Rerun ninja to make sure that dependencies aren't broken.
EXEC ninja-rerun ninja -d explain -v
# Since meson 0.63.0, it generates some extra meta rules, causing the stderr
# output not to be empty here.
# DIFF ninja-rerun.err - <<EOF
# EOF
DIFF ninja-rerun.out - <<EOF
ninja: no work to do.
EOF


EXIT

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


cat >test-arm.asm <<EOF
        AREA |.text|, CODE, READONLY, ALIGN=4, CODEALIGN
        ALIGN 4
        EXPORT func
func PROC
        nop
        ENDP
        END
EOF

cat >test-x86.asm <<EOF
_TEXT SEGMENT ALIGN(16) 'CODE'
PUBLIC func
func PROC
        ret
func ENDP
_TEXT ENDS
END
EOF

ARCH=$(. "${BIN}msvcenv.sh" && echo $ARCH)

case $ARCH in
x86)
    EXEC "" ${BIN}ml /c /Fo test-$ARCH.obj test-x86.asm
    ;;
x64)
    EXEC "" ${BIN}ml64 /c /Fo test-$ARCH.obj test-x86.asm
    ;;
arm)
    EXEC "" ${BIN}armasm test-arm.asm test-$ARCH.obj
    ;;
arm64)
    EXEC "" ${BIN}armasm64 test-arm.asm test-$ARCH.obj
    ;;
esac

EXIT

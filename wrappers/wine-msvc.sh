#!/bin/bash
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

EXE=$1
shift
ARGS=()
while [ $# -gt 0 ]; do
	a=$1
	case $a in
	[-/][A-Za-z][A-Za-z]/*)
		opt=${a:0:3}
		path=${a:3}
		if [ -d "$(dirname "$path")" ] && [ "$(dirname "$path")" != "/" ]; then
			a=${opt}z:$path
		fi
		;;
	/*)
		if [ -d "$(dirname "$a")" ] && [ "$(dirname "$a")" != "/" ]; then
			a=z:$a
		fi
		;;
	*)
		;;
	esac
	ARGS+=("$a")
	shift
done
WINEDEBUG=-all wine64 "$EXE" "${ARGS[@]}" 2> >(sed 's/\r//' | sed 's/z:\([\\/]\)/\1/i' | sed '/^Note:/s,\\,/,g' >&2) | sed 's/\r//' | sed 's/z:\([\\/]\)/\1/i' | sed '/^Note:/s,\\,/,g'
exit $PIPESTATUS

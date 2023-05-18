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

if [ ${#ARGS[@]} -gt 0 ]; then
	# 1. Escape all double-quotes.
	# 2. Enclose each argument with double quotes.
	# 3. Join all arguments with spaces.
	export WINE_MSVC_ARGS=$(printf ' "%s"' "${ARGS[@]//\"/\\\"}")
else
	export WINE_MSVC_ARGS=
fi
# 4. Split the argument string into multiple variables with smaller length.
# https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw
# The maximum length of lpCommandLine for CreateProcess is 32,767 characters.
# https://learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/command-line-string-limitation
n=8191 # The maximum length of the string that you can use at the command prompt is 8191 characters.
export WINE_MSVC_ARGS0=${WINE_MSVC_ARGS:0*$n:$n}
export WINE_MSVC_ARGS1=${WINE_MSVC_ARGS:1*$n:$n}
export WINE_MSVC_ARGS2=${WINE_MSVC_ARGS:2*$n:$n}
export WINE_MSVC_ARGS3=${WINE_MSVC_ARGS:3*$n:$n}
export WINE_MSVC_ARGS4=${WINE_MSVC_ARGS:4*$n:$n}
export WINE_MSVC_ARGS5=${WINE_MSVC_ARGS:5*$n:$n}
export WINE_MSVC_ARGS6=${WINE_MSVC_ARGS:6*$n:$n}
export WINE_MSVC_ARGS7=${WINE_MSVC_ARGS:7*$n:$n}
export WINE_MSVC_ARGS8=${WINE_MSVC_ARGS:8*$n:$n}
export WINE_MSVC_ARGS9=${WINE_MSVC_ARGS:9*$n:$n}

if [ ${#WINE_MSVC_ARGS9} -ge $n ]; then
	echo "Command line arguments are too long." >&2
	exit 1
fi

unixify_path='s/\r// ; s/z:\([\\/]\)/\1/i ; /^Note:/s,\\,/,g'

if [ -d /proc/$$/fd ]; then
	exec {fd1}> >(sed -e "$unixify_path")
	exec {fd2}> >(sed -e "$unixify_path" >&2)

	export WINE_MSVC_STDOUT=/proc/$$/fd/$fd1
	export WINE_MSVC_STDERR=/proc/$$/fd/$fd2
	WINEDEBUG=-all wine64 'C:\Windows\System32\cmd.exe' /C $(dirname $0)/wine-msvc.bat "$EXE" &>/dev/null {fd1}>&- {fd2}>&-
else
	export WINE_MSVC_STDOUT=${TMPDIR:-/tmp}/wine-msvc.stdout.$$
	export WINE_MSVC_STDERR=${TMPDIR:-/tmp}/wine-msvc.stderr.$$

	cleanup() {
		wait
		rm -f $WINE_MSVC_STDOUT $WINE_MSVC_STDERR
	}

	trap cleanup EXIT

	cleanup && mkfifo $WINE_MSVC_STDOUT $WINE_MSVC_STDERR || exit 1

	sed -e "$unixify_path" <$WINE_MSVC_STDOUT &
	sed -e "$unixify_path" <$WINE_MSVC_STDERR >&2 &
	WINEDEBUG=-all wine64 'C:\Windows\System32\cmd.exe' /C $(dirname $0)/wine-msvc.bat "$EXE" &>/dev/null
fi

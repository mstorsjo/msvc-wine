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

MSVCTRICKS_EXE="$(dirname $0)/../msvctricks.exe"
EXE=$1
shift

ARGS=()
for a; do
	path=
	case "$a" in
	[-/][A-Za-z]/*)
		path=${a#??}
		# Rewrite options like -I/absolute/path into -Iz:/absolute/path.
		# This is needed to avoid what seems like a cl.exe/Wine bug combination
		# in some very rare cases, see https://bugs.winehq.org/show_bug.cgi?id=55200
		# for details. In those rare cases, cl.exe fails to find includes in
		# some directories specified with -I/absolute/path but does find them if
		# they have been specified as -Iz:/absolute/path.
		;;
	[-/][A-Za-z][A-Za-z]/*)
		path=${a#???}
		# Rewrite options like -Fo/absolute/path into -Foz:/absolute/path.
		# This doesn't seem to be strictly needed for any known case at the moment, but
		# might have been needed with some version of MSVC or Wine earlier.
		;;
	[-/][A-Za-z][A-Za-z][A-Za-z]*:/*)
		path=${a#*:}
		# Rewrite options like -MANIFESTINPUT:/absolute/path into -MANIFESTINPUT:z:/absolute/path.
		;;
	@*CMakeFiles*.rsp)
		# Rewrite absolute paths in response files like /absolute/path into z:/absolute/path.
		if [[ $EXE == "link.exe" || $EXE == "lib.exe" ]]
		then
      if sed --help 2>&1 | grep '\-i extension' >/dev/null; then
          inplace=(-i '') # BSD sed
      else
          inplace=(-i)    # GNU sed
      fi

  		filepath=$(realpath "${a:1}")
      sed "${inplace[@]}" -E 's@(^|[[:blank:]])((/[^/[:blank:]]*){2,})@\1z:\2@g' "$filepath"
    fi
		;;
	/*)
		# Rewrite options like /absolute/path into z:/absolute/path.
		# This is essential for disambiguating e.g. /home/user/file from the
		# tool option /h with the value ome/user/file.
		path=$a
		;;
	*)
		;;
	esac
	if [ -n "$path" ] && [ -d "$(dirname "$path")" ] && [ "$(dirname "$path")" != "/" ]; then
		opt=${a%$path}
		a=${opt}z:$path
	fi
	ARGS+=("$a")
done

WINE=$(command -v wine64 || command -v wine || false)
export WINEDEBUG=${WINEDEBUG:-"-all"}

if [ -n "$WINE_MSVC_RAW_STDOUT" ]; then
	"$WINE" "$EXE" "${ARGS[@]}"
	exit $?
fi

WINE_MSVC_STDOUT_SED='s/\r//;'"$WINE_MSVC_STDOUT_SED"
WINE_MSVC_STDERR_SED='s/\r//;'"$WINE_MSVC_STDERR_SED"

if [ ! -f "$MSVCTRICKS_EXE" ]; then
	"$WINE" "$EXE" "${ARGS[@]}" 2> >(sed -E "$WINE_MSVC_STDERR_SED" >&2) | sed -E "$WINE_MSVC_STDOUT_SED"
	exit $PIPESTATUS
else
	export WINE_MSVC_STDOUT=${TMPDIR:-/tmp}/wine-msvc.stdout.$$
	export WINE_MSVC_STDERR=${TMPDIR:-/tmp}/wine-msvc.stderr.$$

	cleanup() {
		wait
		rm -f $WINE_MSVC_STDOUT $WINE_MSVC_STDERR
	}

	trap cleanup EXIT

	cleanup && mkfifo $WINE_MSVC_STDOUT $WINE_MSVC_STDERR || exit 1

	"$WINE" "$MSVCTRICKS_EXE" "$EXE" "${ARGS[@]}" &>/dev/null &
	pid=$!
	sed -E "$WINE_MSVC_STDOUT_SED" <$WINE_MSVC_STDOUT     || kill $pid &>/dev/null &
	sed -E "$WINE_MSVC_STDERR_SED" <$WINE_MSVC_STDERR >&2 || kill $pid &>/dev/null &
	wait $pid &>/dev/null
fi

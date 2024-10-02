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

# NOTE: This file should only be sourced

if [ -z $BASE ]; then
  export BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

export OLD_PATH=$PATH
export OLD_WINEPATH=$WINEPATH
export OLD_CC=$CC
export OLD_CXX=$CXX

function deactivate {
  export PATH=$OLD_PATH
  export WINEPATH=$OLD_WINEPATH
  export CC=$OLD_CC
  export CXX=$OLD_CXX
  unset OLD_PATH
  unset OLD_WINEPATH
  unset OLD_CC
  unset OLD_CXX
  unset RC
  unset INCLUDE
  unset LIB
  unset LIBPATH
  unset WINEDLLOVERRIDES
  unset BASE
  unset deactivate
}
MSVCVER=14.41.34120
SDKVER=10.0.22621.0

# This is supplied as an arugment of the source command
ARCH=$1

#SDK=kits\\10
SDK=kits/10

# Try to keep everything modular.
# Use bash ararry as much as possible as it
# allows for easier conversion to windows paths.

BINDIR="$BASE/bin"

MSVCBASE="$BASE/vc"
MSVC="$MSVCBASE/tools/msvc/$MSVCVER"
MSVC_BINDIR=$MSVC/bin/Hostx64/$ARCH
MSVC_INCLUDE=$MSVC/include
MSVC_LIB=$MSVC/lib/$ARCH

# TODO: ATL and MFC
ATL="$MSVC/altmfc"
ATL_INCLUDE="$ATL/include"
ATL_LIB="$ATL/lib/$ARCH"

SDKBASE="$BASE/$SDK"
SDK_INCLUDE="$SDKBASE/include/$SDKVER"
SDK_LIBDIR="$SDKBASE/lib/$SDKVER/"
SDK_BINDIR=$SDKBASE/bin/$SDKVER/$ARCH
SDK_INCLUDES=("$SDK_INCLUDE/shared" "$SDK_INCLUDE/ucrt" "$SDK_INCLUDE/um" "$SDK_INCLUDE/winrt" "$SDK_INCLUDE/km")
SDK_LIBS=("$SDK_LIBDIR/ucrt/$ARCH" "$SDK_LIBDIR/um/$ARCH" "$SDK_LIBDIR/ucrt_enclave/$ARCH")

# TODO: MSBUILD
MSBUILD=$BASE/MSBuild/Current
MSBUILD_BINDIR=$MSBUILD/Bin/amd64

_INCLUDES=("$ATL_INCLUDE" "$MSVC_INCLUDE" "${SDK_INCLUDES[@]}")
_LIBS=($ATL_LIB $MSVC_LIB "${SDK_LIBS[@]}")

export INCLUDE_WINE_UNIX="${_INCLUDES[@]}"

# Not sure how to eliminate temp variables
# Cannot use a function as arrays are not preserved
# {// / /\\\\}
#  ^^   tells bash to replace
#     ^ replace with \\\\
_TEMP1=(${_INCLUDES[@]////\\\\})
# {/#/z:}
#  ^^    select start of variable
#     ^^ repace with z:
_TEMP1=(${_TEMP1[@]/#/z:})
# IFS - interfield seperator
IFS=";"
export INCLUDE="${_TEMP1[*]}"
unset IFS
_TEMP1=(${_LIBS[@]////\\\\})
_TEMP1=(${_TEMP1[@]/#/z:})
IFS=";"
export LIB="${_TEMP1[*]}"
unset IFS
export LIBPATH="$LIB"
export PATH=$(
  ARR=($BINDIR $MSBUILD_BINDIR $MSVC_BINDIR $SDK_BINDIR $PATH)
  IFS=':'
  echo "${ARR[*]}"
)
# "$MSVCDIR\\bin\\Hostx64\\x64" is included in PATH for DLLs.

# Keep as array until the very end.
export WINEPATH=$(
  ARR=($MSBUILD_BINDIR $MSVC_BINDIR $SDK_BINDIR)
  _TEMP=(${ARR[@]/#/z:})
  _TEMP=(${_TEMP[@]////\\\\})
  IFS=';'
  echo "${_TEMP[*]}"
)
export WINEDLLOVERRIDES="vcruntime140=n;vcruntime140_1=n"

# this is used to run applications throught scripts,
# it is also available after sourcing in the shell.
#
# used as `run_exe program.exe`
function run_exe {
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
    /*)
      # Rewrite options like /absolute/path into z:/absolute/path.
      # This is essential for disambiguating e.g. /home/user/file from the
      # tool option /h with the value ome/user/file.
      path=$a
      ;;
    *) ;;
    esac
    if [ -n "$path" ] && [ -d "$(dirname "$path")" ] && [ "$(dirname "$path")" != "/" ]; then
      opt=${a%$path}
      a=${opt}z:$path
    fi
    ARGS+=("$a")
  done
  WINEPREFX=$BASE/wine WINEARCH=win64 wine $BASE/msvctricks.exe "${ARGS[@]}"
}

# Export c and cpp compiler and rc.
# This should be more robust like ensuring that other programs are set.
export CC="$BINDIR/cl"
export CXX="$BINDIR/cl"
export RC="$BINDIR/rc"

#!/bin/bash
#
# Copyright (c) 2024 Huang Qinjin
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

host=x64
if [ "$(uname -m)" = "aarch64" ]; then
    host=arm64
fi

BASE=$(. "${BIN}msvcenv.sh" && echo $BASE)
ARCH=$(. "${BIN}msvcenv.sh" && echo $ARCH)

if [ "$host" = "$ARCH" ]; then
    vcvars_arch=${ARCH}
else
    vcvars_arch=${host}_${ARCH}
fi

cat >test-$vcvars_arch.bat <<EOF
@echo off

set "CWD=%CD%"

set VSCMD_START_DIR=
call $BASE\VC\Auxiliary\Build\vcvarsall.bat $vcvars_arch
if %errorlevel% neq 0 exit /B %errorlevel%

if not "%CWD%"=="%CD%" (
    echo ERROR: vcvarsall.bat changed CWD to %CD%.
    exit /B 2
)

set "WindowsSDKVersion=%WindowsSDKVersion:\=%"

call :SaveUnixPath VSINSTALLDIR
call :SaveUnixPath VCToolsInstallDir
call :SaveUnixPath WindowsSdkDir
call :SaveVariable WindowsSDKVersion
call :SaveUnixPath UniversalCRTSdkDir
call :SaveVariable UCRTVersion
call :SearchInPath cl.exe
call :SearchInPath rc.exe
call :SearchInPath MSBuild.exe
exit /B 0

:SearchInPath
setlocal EnableDelayedExpansion
set "f=%1"
set "f=%f:.=_%"
for /F "delims=" %%G in ('where %1') do (
    set "%f%=%%G"
    call :SaveUnixPath %f%
    exit /B 0
)
exit /B 1

:SaveUnixPath
setlocal EnableDelayedExpansion
set "p=!%1!"
if "%p:~-1%"=="\" set "p=%p:~0,-1%"
for /F "delims=" %%G in ('winepath -u "%p%"') do (
    set "%1=%%G"
    call :SaveVariable %1
)
exit /B 0

:SaveVariable
setlocal EnableDelayedExpansion
echo %1="!%1!" >> $vcvars_arch-env.txt
exit /B 0
EOF


TestVariable() {
    if [ "${!1}" != "$2" ]; then
        echo "ERROR: $1=\"${!1}\""
        return 1
    fi
    return 0
}

TestRealPath() {
    if [ "$(readlink -f "${!1}")" != "$(readlink -f "$2")" ]; then
        echo "ERROR: $1=\"${!1}\""
        return 1
    fi
    return 0
}

EXEC "" WINEDEBUG=-all $(command -v wine64 || command -v wine) cmd /c test-$vcvars_arch.bat || EXIT
tr -d '\r' <$vcvars_arch-env.txt >$vcvars_arch-env
. $vcvars_arch-env

SDKBASE=$(. "${BIN}msvcenv.sh" && echo $SDKBASE)
SDKBASE=${SDKBASE//\\//}
SDKBASE=${SDKBASE#z:}

MSVCDIR=$(. "${BIN}msvcenv.sh" && echo $MSVCDIR)
MSVCDIR=${MSVCDIR//\\//}
MSVCDIR=${MSVCDIR#z:}

EXEC "" TestRealPath VSINSTALLDIR       $(. "${BIN}msvcenv.sh" && echo $BASE_UNIX)
EXEC "" TestRealPath VCToolsInstallDir  $MSVCDIR
EXEC "" TestRealPath WindowsSdkDir      $SDKBASE
EXEC "" TestVariable WindowsSDKVersion  $(. "${BIN}msvcenv.sh" && echo $SDKVER)
EXEC "" TestRealPath UniversalCRTSdkDir $SDKBASE
EXEC "" TestVariable UCRTVersion        $(. "${BIN}msvcenv.sh" && echo $SDKVER)

# Below tests require where.exe (available in Wine 9.3+).
printf "%s\n" wine-9.3 $(WINEDEBUG=-all $(command -v wine64 || command -v wine) --version) | sort -VC || EXIT

EXEC "" TestRealPath cl_exe             $(. "${BIN}msvcenv.sh" && echo $BINDIR)/cl.exe
EXEC "" TestRealPath rc_exe             $(. "${BIN}msvcenv.sh" && echo $SDKBINDIR)/rc.exe
EXEC "" TestRealPath MSBuild_exe        $(. "${BIN}msvcenv.sh" && echo $MSBUILDBINDIR)/MSBuild.exe

EXIT

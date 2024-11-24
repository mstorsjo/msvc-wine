#!/bin/bash
set -e
if [ -z ${BASE} ]; then
  echo "Please source msvcenv.sh before running any programs"
  exit 1
fi

EXENAME="$(basename $0).exe"
ARCH=xUnknown
. $BASE/msvcenv.sh $ARCH
run_exe "$EXENAME" "$@"

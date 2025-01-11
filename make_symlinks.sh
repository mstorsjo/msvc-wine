#!/usr/bin/bash

BASE=$(
  cd "$(dirname $0)"
  pwd
)
ARCH=$1
BINDIR="$BASE/bin/$ARCH"

mkdir -p $BINDIR

function make_symlink {
  ln -s $BINDIR/run_exe.sh $BINDIR/$1
}

cat $BASE/run_exe.sh | sed "s/xUnknown/${ARCH}/" | cat >$BINDIR/run_exe.sh

make_symlink cl
make_symlink link
make_symlink rc
make_symlink oleview

chmod +x $BINDIR/run_exe.sh

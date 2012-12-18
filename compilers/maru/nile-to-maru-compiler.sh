#!/bin/sh

DIR="$( cd "$( dirname "$0" )" && pwd )"

set -x

#make -C $DIR/maru eval tpeg.l
#$DIR/maru/eval -b $DIR/maru/boot.l -L $DIR/maru/ $DIR/nile-compiler.l \
#  maru $DIR/../prelude.nl $@

make -C $DIR/maru eval gceval tpeg.l
$DIR/maru/gceval -b $DIR/maru/boot.l -L $DIR/maru/ $DIR/nile-compiler.l \
  $DIR maru $@

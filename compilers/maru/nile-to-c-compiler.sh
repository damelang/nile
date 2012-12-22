#!/bin/sh

DIR="$( cd "$( dirname "$0" )" && pwd )"

set -x

make -C $DIR/maru eval gceval tpeg.l
$DIR/maru/gceval -b $DIR/maru/boot.l -L $DIR/maru/ $DIR/nile-compiler.l \
  $DIR c $@

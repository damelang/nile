#!/bin/sh

set -x
GEZIRA_DIR=~/src/gezira-clean/nl
GEZIRA_SRC="$GEZIRA_DIR/types.nl
            $GEZIRA_DIR/bezier.nl
            $GEZIRA_DIR/compositor.nl
            $GEZIRA_DIR/gradient.nl
            $GEZIRA_DIR/rasterize.nl
            $GEZIRA_DIR/texture.nl"

make -C maru gceval
maru/gceval -g -b maru/boot.l -L maru/ nile-compiler.l $GEZIRA_SRC

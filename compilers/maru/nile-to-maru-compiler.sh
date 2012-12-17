#!/bin/sh

GEZIRA_DIR=~/src/gezira-clean/nl
GEZIRA_SRC="$GEZIRA_DIR/types.nl
            $GEZIRA_DIR/rasterize.nl
            $GEZIRA_DIR/bezier.nl
            $GEZIRA_DIR/stroke.nl
            $GEZIRA_DIR/compositor.nl
            $GEZIRA_DIR/gradient.nl
            $GEZIRA_DIR/texture.nl
            $GEZIRA_DIR/filter.nl"
set -x
make -C maru eval gceval tpeg.l
maru/gceval -g -b maru/boot.l -L maru/ nile-compiler.l maru gezira $GEZIRA_SRC

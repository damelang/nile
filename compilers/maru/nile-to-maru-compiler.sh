#!/bin/sh

set -x
#make -C maru eval tpeg.l
#maru/eval -b maru/boot.l -L maru/ nile-compiler.l maru $@
make -C maru eval gceval tpeg.l
maru/gceval -g -b maru/boot.l -L maru/ nile-compiler.l maru $@

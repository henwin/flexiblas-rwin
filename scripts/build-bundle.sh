#!/usr/bin/env bash
# Inside the image from docker/Dockerfile, after scripts/build-mxe.sh: build
# the FlexiBLAS bundle with patches/r-dev-web/flexiblas_bundle/build_ucrt.sh,
# as R-core builds the Tcl/Tk bundle, and unpack it into dist/FlexiBLAS.
set -euo pipefail
WORK=${WORK:-/work}
export PATH=/usr/lib/mxe/usr/bin:$PATH
b=$(mktemp -d)
cp "$WORK"/patches/r-dev-web/flexiblas_bundle/{build_ucrt.sh,flexiblas.diff} "$b"
cd "$b"
bash -x ./build_ucrt.sh 2>&1 | tee build_ucrt.out | tail -40
rm -rf "$WORK/dist/FlexiBLAS"
mkdir -p "$WORK/dist"
cp FlexiBLAS.zip "$WORK/dist/"
cp -r FlexiBLAS "$WORK/dist/"

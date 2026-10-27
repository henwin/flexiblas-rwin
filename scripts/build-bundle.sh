#!/usr/bin/env bash
# Inside the image from docker/Dockerfile, after scripts/build-mxe.sh: build
# the FlexiBLAS bundle with patches/r-dev-web/flexiblas_bundle/build_ucrt.sh,
# as R-core builds the Tcl/Tk bundle, and unpack it into dist/FlexiBLAS.
set -euo pipefail
WORK=${WORK:-/work}
export PATH=/usr/lib/mxe/usr/bin:$PATH
b=$(mktemp -d)
cp "$WORK"/patches/r-dev-web/flexiblas_bundle/build_ucrt.sh "$b"
# flexiblas.diff, which build_ucrt.sh applies as tcl_bundle applies tcl.diff
cat "$WORK"/patches/flexiblas/*.patch > "$b/flexiblas.diff"
cd "$b"
# CMake takes CMAKE_EXPORT_COMPILE_COMMANDS from the environment, so the
# flags of the reference BLAS and LAPACK can be shown without changing the
# bundle script.
CMAKE_EXPORT_COMPILE_COMMANDS=ON bash -x ./build_ucrt.sh 2>&1 | tee build_ucrt.out | tail -40
cc=$(find . -name compile_commands.json | head -1)
if [ -n "$cc" ]; then
    for f in dgemm dpotrf; do
        grep -o "\"command\": \"[^\"]*/$f\\.f[^\"]*\"" "$cc" | head -1 || true
    done
else
    echo "no compile_commands.json (CMake older than 3.17?)"
fi
rm -rf "$WORK/dist/FlexiBLAS"
mkdir -p "$WORK/dist"
cp FlexiBLAS.zip "$WORK/dist/"
cp -r FlexiBLAS "$WORK/dist/"

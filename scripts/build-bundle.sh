#!/usr/bin/env bash
# Inside the image from docker/Dockerfile, after scripts/build-mxe.sh: build
# the FlexiBLAS bundle with patches/r-dev-web/flexiblas_bundle/build_ucrt.sh,
# as R-core builds the Tcl/Tk bundle, for the target given (x86_64 by
# default, or aarch64), and unpack it into dist/FlexiBLAS (dist/FlexiBLAS-aarch64).
set -euo pipefail
WORK=${WORK:-/work}
target=${1:-x86_64}
case $target in
    x86_64)  mxe=/opt/mxe; name=FlexiBLAS ;;
    aarch64) mxe=/opt/mxe-aarch64; name=FlexiBLAS-aarch64 ;;
    *) echo "unknown target $target" >&2; exit 2 ;;
esac
export PATH=$mxe/usr/bin:$PATH
b=$(mktemp -d)
cp "$WORK"/patches/r-dev-web/flexiblas_bundle/build_ucrt.sh "$b"
# flexiblas.diff, which build_ucrt.sh applies as tcl_bundle applies tcl.diff
cat "$WORK"/patches/flexiblas/*.patch > "$b/flexiblas.diff"
# the OpenBLAS patches as MXE has them after build-mxe.sh, R-core's and ours,
# for the pthreads build of the bundle
cp "$mxe"/src/openblas-*.patch "$b"
cd "$b"
# the pthreads OpenBLAS the bundle builds, kept in bundle-out by the hash of
# the bundle script and the OpenBLAS patches, as build-mxe.sh keeps the MXE
# build of OpenBLAS
h=$(cat "$WORK"/patches/r-dev-web/flexiblas_bundle/build_ucrt.sh "$WORK"/patches/openblas/*.patch | sha256sum | cut -c1-12)
cache=$WORK/bundle-out/libopenblas-pthreads-$target-$h.a
[ ! -f "$cache" ] || cp "$cache" libopenblas-pthreads.a
# CMake takes CMAKE_EXPORT_COMPILE_COMMANDS from the environment, so the
# flags of the reference BLAS and LAPACK can be shown without changing the
# bundle script.
status=0
CMAKE_EXPORT_COMPILE_COMMANDS=ON bash -x ./build_ucrt.sh $target 2>&1 | tee build_ucrt.out | tail -40 || status=$?
# the whole output of the bundle build, for the workflow's report, and the
# pthreads OpenBLAS for the cache, whether or not the bundle was finished
mkdir -p "$WORK/dist"; cp build_ucrt.out "$WORK/dist/build_ucrt-$target.out"
if [ -f libopenblas-pthreads.a ] && [ ! -f "$cache" ]; then
    mkdir -p "$(dirname "$cache")"; cp libopenblas-pthreads.a "$cache"
fi
[ "$status" = 0 ] || exit "$status"
cc=$(find . -name compile_commands.json | head -1)
if [ -n "$cc" ]; then
    for f in dgemm dpotrf; do
        grep -o "\"command\": \"[^\"]*/$f\\.f[^\"]*\"" "$cc" | head -1 || true
    done
else
    echo "no compile_commands.json (CMake older than 3.17?)"
fi
rm -rf "$WORK/dist/$name"
mkdir -p "$WORK/dist"
cp FlexiBLAS.zip "$WORK/dist/$name.zip"
cp -r FlexiBLAS "$WORK/dist/$name"

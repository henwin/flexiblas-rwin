#!/usr/bin/env bash
# Inside the image from docker/Dockerfile, with this repository at /work:
# apply patches/rtools-mxe/ and patches/openblas/ to R's MXE tree and
# rebuild OpenBLAS with MXE, as R-core would rebuild the toolchain, for the
# target given (x86_64 by default, or aarch64, whose tree the image has
# when built with WITH_AARCH64=yes). The files OpenBLAS installs are kept
# in mxe-out/openblas-TARGET-HASH.tar, HASH from the patches and this
# script; when that exists, they are unpacked instead.
set -euo pipefail
WORK=${WORK:-/work}
target=${1:-x86_64}
case $target in
    x86_64)  cd /opt/mxe; triplet=x86_64-w64-mingw32.static.posix; rtarget= ;;
    aarch64) cd /opt/mxe-aarch64; triplet=aarch64-w64-mingw32.static.posix; rtarget=R_TARGET=aarch64 ;;
    *) echo "unknown target $target" >&2; exit 2 ;;
esac

for p in "$WORK"/patches/rtools-mxe/*.patch; do
    patch -p0 -N < "$p"
done
# the OpenBLAS patches, under MXE's names after R-core's openblas-1 and -2;
# MXE applies src/openblas-*.patch in order
for p in "$WORK"/patches/openblas/*.patch; do
    f=$(basename "$p"); n=$((10#${f%%-*} + 2))
    cp "$p" "src/openblas-$n-${f#*-}"
done

h=$(cat "$WORK"/patches/rtools-mxe/*.patch "$WORK"/patches/openblas/*.patch "$WORK"/docker/Dockerfile "$WORK"/scripts/build-mxe.sh | sha256sum | cut -c1-12)
cache=$WORK/mxe-out/openblas-$target-$h.tar
if [ -f "$cache" ]; then
    tar -xf "$cache"
    exit 0
fi

# MXE rebuilds a package whose dependencies have no build stamp. Stamp the
# toolchain and libraries that came from the tarballs without rebuilding
# them (the howto's dry run), limited to what OpenBLAS needs.
deps="cc fc pthreads"
for i in 1 2 3; do make -j MXE_BUILD_DRY_RUN=1 $rtarget $deps > /dev/null 2>&1 || true; done
find usr -name '*.dry-run' -delete

touch "$WORK/.mxe-start"
make -j"$(nproc)" $rtarget openblas || { tail -60 log/openblas_*; exit 1; }
mkdir -p "$(dirname "$cache")"
find usr -newer "$WORK/.mxe-start" \( -type f -o -type l \) -print0 |
    tar -cf "$cache" --null -T -
rm "$WORK/.mxe-start"
tar -tf "$cache" | grep -v "^usr/$triplet/include/openblas/" | head -20

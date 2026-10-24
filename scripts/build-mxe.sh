#!/usr/bin/env bash
# Inside the image from docker/Dockerfile, with this repository at /work:
# apply patches/rtools-mxe/ to R's MXE tree and rebuild OpenBLAS with MXE,
# as R-core would rebuild the toolchain. The files OpenBLAS installs are
# kept in mxe-out/openblas.tar; when that exists, they are unpacked instead.
set -euo pipefail
WORK=${WORK:-/work}
cd /opt/mxe

for p in "$WORK"/patches/rtools-mxe/*.patch; do
    patch -p0 -N < "$p"
done

cache=$WORK/mxe-out/openblas.tar
if [ -f "$cache" ]; then
    tar -xf "$cache"
    exit 0
fi

# MXE rebuilds a package whose dependencies have no build stamp. Stamp the
# toolchain and libraries that came from the tarballs without rebuilding
# them (the howto's dry run), limited to what OpenBLAS needs.
deps="cc fc pthreads"
for i in 1 2 3; do make -j MXE_BUILD_DRY_RUN=1 $deps > /dev/null 2>&1 || true; done
find usr -name '*.dry-run' -delete

touch "$WORK/.mxe-start"
make -j"$(nproc)" openblas || { tail -60 log/openblas_*; exit 1; }
mkdir -p "$(dirname "$cache")"
find usr -newer "$WORK/.mxe-start" \( -type f -o -type l \) -print0 |
    tar -cf "$cache" --null -T -
rm "$WORK/.mxe-start"
tar -tf "$cache" | grep -v '^usr/x86_64-w64-mingw32.static.posix/include/openblas/' | head -20

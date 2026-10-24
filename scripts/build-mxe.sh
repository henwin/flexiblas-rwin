#!/usr/bin/env bash
# Inside the image from docker/mxe.Dockerfile, with this repository at /work:
# apply patches/rtools-mxe/ to R's MXE tree, rebuild OpenBLAS and FlexiBLAS
# with MXE, and copy the FlexiBLAS DLLs and configuration to dist/.
set -euo pipefail
WORK=${WORK:-/work}
TARGET=x86_64-w64-mingw32.static.posix
cd /opt/mxe

for p in "$WORK"/patches/rtools-mxe/*.patch; do
    patch -p0 -N < "$p"
done

# MXE rebuilds a package whose dependencies have no build stamp. Stamp the
# toolchain and libraries that came from the tarballs without rebuilding
# them (the howto's dry run), limited to what OpenBLAS and FlexiBLAS need.
deps="cc fc pthreads dlfcn-win32"
for i in 1 2 3; do make -j MXE_BUILD_DRY_RUN=1 $deps > /dev/null 2>&1 || true; done
find usr -name '*.dry-run' -delete

# A placeholder checksum is filled in from the download; print it so that
# the recipe can be updated.
for pkg in flexiblas; do
    if grep -q '_CHECKSUM := 0\{64\}' src/$pkg.mk; then
        make update-checksum-$pkg
        grep '_CHECKSUM' src/$pkg.mk
    fi
done

make -j"$(nproc)" openblas flexiblas || {
    for f in log/openblas_* log/flexiblas_*; do
        [ -f "$f" ] && { echo "== $f"; tail -60 "$f"; }
    done
    exit 1
}

out=$WORK/dist
mkdir -p "$out"
cp usr/$TARGET/bin/libflexiblas*.dll "$out/"
cp -r usr/$TARGET/bin/flexiblas "$out/"
cp -r usr/$TARGET/etc "$out/"
usr/bin/$TARGET-objdump -p "$out/libflexiblas.dll" | grep 'DLL Name'
ls -la "$out"

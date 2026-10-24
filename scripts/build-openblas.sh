#!/usr/bin/env bash
# Build OpenBLAS with the Rtools45 toolchain as two FlexiBLAS backends:
# libopenblas_threads.dll and libopenblas_openmp.dll, each self-contained.
set -euo pipefail

OPENBLAS_VERSION=${OPENBLAS_VERSION:-0.3.34}
TARGET=x86_64-w64-mingw32.static.posix
MXE=/usr/lib/mxe/usr
export PATH=$MXE/bin:$PATH
ROOT=$PWD
OUT=${OUT:-$ROOT/openblas-dist}
mkdir -p "$OUT" work
cd work

EXCL=libssp.a:libssp_nonshared.a:libgcc.a:libgcc_eh.a:libgfortran.a:libquadmath.a:libgomp.a:libwinpthread.a

[ -d "OpenBLAS-$OPENBLAS_VERSION" ] || git clone -q --depth 1 --branch "v$OPENBLAS_VERSION" \
    https://github.com/OpenMathLib/OpenBLAS.git "OpenBLAS-$OPENBLAS_VERSION"

build() {
    local name=$1 openmp=$2
    local src=ob-$name
    rm -rf "$src"
    cp -r "OpenBLAS-$OPENBLAS_VERSION" "$src"
    # A static archive only; the DLL is linked below so that its exports
    # can be controlled. 32-bit integers, as R uses.
    make -C "$src" -j"$(nproc)" -s \
        CC=$TARGET-gcc FC=$TARGET-gfortran AR=$TARGET-ar RANLIB=$TARGET-ranlib \
        HOSTCC=gcc OSNAME=WINNT BINARY=64 \
        TARGET=HASWELL DYNAMIC_ARCH=1 ${DYNAMIC_LIST:+DYNAMIC_LIST="$DYNAMIC_LIST"} \
        USE_THREAD=1 USE_OPENMP=$openmp NUM_THREADS=64 NO_AFFINITY=1 \
        NO_SHARED=1 NO_CBLAS=0 NO_LAPACKE=1 \
        libs netlib
    local lib
    lib=$(ls "$src"/libopenblas*.a | grep -v '_p\?-r' | head -1 || true)
    [ -n "$lib" ] || lib=$(ls "$src"/libopenblas*.a | head -1)
    local omp=()
    [ "$openmp" = 1 ] && omp=(-fopenmp)
    $TARGET-gfortran -shared -o "$OUT/libopenblas_$name.dll" \
        -Wl,--whole-archive "$lib" -Wl,--no-whole-archive \
        "${omp[@]}" -static "-Wl,--exclude-libs,$EXCL"
}

build threads 0
build openmp 1
ls -la "$OUT"

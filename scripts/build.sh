#!/usr/bin/env bash
# Build FlexiBLAS, an OpenBLAS backend, a forwarding Rblas.dll and the test
# shim with the Rtools45 toolchain; stage the DLLs in dist/.
set -euo pipefail

FLEXIBLAS_VERSION=${FLEXIBLAS_VERSION:-3.5.0}
R_VERSION=${R_VERSION:-4.6.1}
TARGET=x86_64-w64-mingw32.static.posix
MXE=/usr/lib/mxe/usr
export PATH=$MXE/bin:$PATH
ROOT=$PWD
DIST=$ROOT/dist
mkdir -p "$DIST" work
cd work

# Runtime libraries must not be re-exported from our DLLs: libssp's
# __stack_chk_fail otherwise clashes, and libgomp's symbols would leak.
EXCL=libssp.a:libssp_nonshared.a:libgcc.a:libgcc_eh.a:libgfortran.a:libquadmath.a:libgomp.a:libwinpthread.a:libdl.a

# -- FlexiBLAS ---------------------------------------------------------------
[ -d flexiblas ] || git clone -q --depth 1 --branch "v$FLEXIBLAS_VERSION" \
    https://github.com/mpimd-csc/flexiblas.git
for p in "$ROOT"/patches/*.patch; do
    git -C flexiblas apply "$p"
done
$TARGET-cmake -S flexiblas -B build-fb \
    -DBUILD_SHARED_LIBS=ON -DBLAS_AUTO_DETECT=OFF -DINTEGER8=OFF \
    -DTESTS=OFF -DEXAMPLES=OFF -DLTO=OFF \
    -Ddlfcn-win32_DIR="$ROOT/cmake" \
    "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--exclude-libs,$EXCL"
$MXE/x86_64-pc-linux-gnu/bin/cmake --build build-fb -j"$(nproc)"
cp build-fb/bin/*.dll build-fb/bin/*.exe "$DIST/"

# -- OpenBLAS backend from Rtools' static, OpenMP-threaded libopenblas.a -----
$TARGET-gfortran -shared -o "$DIST/libopenblas.dll" \
    -Wl,--whole-archive "$MXE/$TARGET/lib/libopenblas.a" -Wl,--no-whole-archive \
    -fopenmp -static "-Wl,--exclude-libs,$EXCL"

# -- Forwarding Rblas.dll ----------------------------------------------------
# Export exactly what R's own Rblas.dll exports, each forwarded to
# libflexiblas.dll, so that R.dll and Rlapack.dll reach one FlexiBLAS instance.
exports() {
    $TARGET-objdump -p "$1" |
        awk '/\[Ordinal\/Name Pointer\] Table/{f=1;next} f&&NF==0{exit} f{print $NF}' |
        grep -v '^Name$' | sort
}
[ -f "R-$R_VERSION-win.exe" ] || curl -sSfLO \
    "https://cran.r-project.org/bin/windows/base/R-$R_VERSION-win.exe"
innoextract -q -d rwin -I app/bin/x64 "R-$R_VERSION-win.exe"
exports rwin/app/bin/x64/Rblas.dll > rblas.exports
exports "$DIST/libflexiblas.dll" > flexiblas.exports
missing=$(comm -23 rblas.exports flexiblas.exports)
if [ -n "$missing" ]; then
    echo "libflexiblas.dll lacks Rblas exports: $missing" >&2
    exit 1
fi
{
    echo "LIBRARY Rblas.dll"
    echo "EXPORTS"
    sed 's/.*/& = libflexiblas.&/' rblas.exports
} > Rblas.def
echo 'void rblas_forwarder(void) {}' > fwd.c
$TARGET-gcc -shared -nostdlib -Wl,-e,0 -o "$DIST/Rblas.dll" fwd.c Rblas.def

# -- Test shim: calls the FlexiBLAS API in the loaded libflexiblas.dll ---------
$TARGET-gcc -shared -O2 -o "$DIST/rfbtest.dll" "$ROOT/shim/rfbtest.c"

cp "$ROOT/flexiblasrc" "$DIST/"
ls -la "$DIST"

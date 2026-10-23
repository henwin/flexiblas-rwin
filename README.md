# flexiblas-rwin

Experiments towards runtime-switchable BLAS/LAPACK for R on Windows through FlexiBLAS 3.5.0.

FlexiBLAS, an OpenBLAS backend and a forwarding `Rblas.dll` are cross-built on Linux with the Rtools45 toolchain, which CRAN publishes as tarballs of the MXE tree used to build Rtools. `scripts/setup-toolchain.sh` assembles that tree at `/usr/lib/mxe/usr` and works around the parts the tarballs leave out. `scripts/build.sh` builds everything into `dist/`.

The forwarding `Rblas.dll` exports exactly the symbols of R's own `Rblas.dll`, each forwarded to `libflexiblas.dll`. Since both `R.dll` and `Rlapack.dll` import `Rblas.dll`, all BLAS calls in R, including those made inside R's LAPACK, go through one FlexiBLAS instance. Backends are listed in `flexiblasrc`, found through `FLEXIBLAS_CONFIG`.

The workflow builds on `ubuntu-24.04`, then installs R from CRAN on `windows-2025`, drops the DLLs into `bin\x64` and runs `tests/test-flexiblas.R`. The test compares results between the NETLIB and OpenBLAS backends and switches backend and thread count within one session, using a small shim (`shim/rfbtest.c`) that calls the FlexiBLAS API in the loaded `libflexiblas.dll`.

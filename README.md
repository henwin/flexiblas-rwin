# flexiblas-rwin

Experiments towards runtime-switchable BLAS/LAPACK for R on Windows through FlexiBLAS 3.5.0.

FlexiBLAS, OpenBLAS backends and forwarding `Rblas.dll` and `Rlapack.dll` are cross-built on Linux with the Rtools45 toolchain, which CRAN publishes as tarballs of the MXE tree used to build Rtools. `docker/Dockerfile` defines the build environment: `scripts/setup-toolchain.sh` assembles that tree at `/usr/lib/mxe/usr` and works around the parts the tarballs leave out. `bash scripts/build-in-docker.sh` builds the image and runs `scripts/build-openblas.sh` (only when `openblas-dist/` is missing, about two hours) and `scripts/build.sh`, leaving the DLLs in `dist/`. The same command runs locally, in WSL and in GitHub Actions.

The forwarding `Rblas.dll` and `Rlapack.dll` export exactly the symbols of R's own DLLs, forwarded to `libflexiblas.dll`; the four LAPACK symbols FlexiBLAS lacks go to R's original LAPACK, kept as `Rlapack_ref.dll`. All BLAS and LAPACK calls in R therefore go through one FlexiBLAS instance. Backends are listed in `flexiblasrc`, found through `FLEXIBLAS_CONFIG`.

The workflow builds on `ubuntu-24.04`, then installs R from CRAN on `windows-2025`, drops the DLLs into `bin\x64` and runs `tests/test-flexiblas.R`. The test compares results between the NETLIB and OpenBLAS backends and switches backend and thread count within one session, using a small shim (`shim/rfbtest.c`) that calls the FlexiBLAS API in the loaded `libflexiblas.dll`.

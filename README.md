# flexiblas-rwin

Experiments towards runtime-switchable BLAS/LAPACK for R on Windows through FlexiBLAS.

FlexiBLAS and OpenBLAS are built with MXE recipes in R's own MXE tree for Rtools45 (R-dev SVN, `ucrt3/toolchain_libs/mxe`). `docker/Dockerfile` checks out that tree at the revision that produced Rtools45 and sets it up from CRAN's pre-built toolchain tarballs, as R-core's howto describes. `scripts/build-mxe.sh` applies `patches/rtools-mxe/`, which adds `flexiblas.mk` and updates `openblas.mk` to 0.3.34, and runs `make openblas flexiblas`. `scripts/forwarders.sh` then generates the forwarding `Rblas.dll` and `Rlapack.dll`. `bash scripts/build-in-docker.sh` runs both in the container and leaves the result in `dist/`; the same command runs locally, in WSL and in GitHub Actions.

The patches are kept by destination. `patches/rtools-mxe/` is the change to Rtools; it carries copies of `patches/flexiblas/` and `patches/openblas/`, which are the changes to send to those projects, and `patches/r-flexiblas/` is the Windows support for the R package.

The forwarding `Rblas.dll` and `Rlapack.dll` export exactly the symbols of R's own DLLs, forwarded to `libflexiblas.dll`; the four LAPACK symbols FlexiBLAS lacks go to R's original LAPACK, kept as `Rlapack_ref.dll`. All BLAS and LAPACK calls in R therefore go through one FlexiBLAS instance.

The workflow builds on `ubuntu-24.04`, then installs R from CRAN on `windows-2025` and runs the tests in `tests/`, using a small shim (`shim/rfbtest.c`) that calls the FlexiBLAS API in the loaded `libflexiblas.dll`, and the patched R package.

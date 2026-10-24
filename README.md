# flexiblas-rwin

Experiments towards runtime-switchable BLAS/LAPACK for R on Windows through FlexiBLAS.

Everything follows R-core's own Windows build. `docker/Dockerfile` checks out R's MXE tree for Rtools45 (R-dev SVN, `ucrt3/toolchain_libs/mxe`) at the revision that produced Rtools45 and sets it up from CRAN's pre-built toolchain tarballs, as R-core's howto describes. `scripts/build-mxe.sh` applies `patches/rtools-mxe/`, which updates `openblas.mk` to 0.3.34 with a thread-count fix and a fixed `NUM_THREADS`, and rebuilds OpenBLAS, as R-core would rebuild the toolchain. `scripts/build-bundle.sh` then builds the FlexiBLAS bundle with `patches/r-dev-web/flexiblas_bundle/`, scripts modelled on R-core's `tcl_bundle`, which builds the Tcl/Tk bundle that R ships. `scripts/forwarders.sh` finally generates the forwarding `Rblas.dll` and `Rlapack.dll`. `bash scripts/build-in-docker.sh` runs all three in the container and leaves the bundle in `dist/FlexiBLAS` and the forwarders in `dist/forwarders`; the same command runs locally, in WSL and in GitHub Actions.

The bundle has R's layout: the DLLs in `bin/x64`, the OpenBLAS backend in `bin/x64/flexiblas`, and the configuration in `etc`, so it is copied over `R_HOME`. The forwarding `Rblas.dll` and `Rlapack.dll` export exactly the symbols of R's own DLLs, forwarded to `libflexiblas.dll`; the four LAPACK symbols FlexiBLAS lacks go to R's original LAPACK, kept as `Rlapack_ref.dll`. All BLAS and LAPACK calls in R therefore go through one FlexiBLAS instance.

The patches are kept by destination. `patches/rtools-mxe/` is the change to Rtools and carries a copy of `patches/openblas/`; `patches/r-dev-web/` holds changes and additions to R-core's Windows build scripts, the FlexiBLAS bundle included, which carries `patches/flexiblas/` as `flexiblas.diff`; `patches/r-flexiblas/` is the Windows support for the R package.

The workflow builds on `ubuntu-24.04`, then installs R from CRAN on `windows-2025`, installs the patched flexiblas package and runs the tests in `tests/` through it. `r-check.yml` builds R from SVN and runs `make check-all` with FlexiBLAS installed.

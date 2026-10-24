## Run under FLEXIBLAS_HOOK=PROFILE. If R's LAPACK goes through FlexiBLAS,
## the profile records dpotrf and dgesv; if only R's reference LAPACK ran on
## top of FlexiBLAS's BLAS, it would record dsyrk, dgemm and dtrsm instead.
dyn.load(file.path(R.home("bin"), "rfbtest.dll"))
id <- .C("rfb_load", name = "OPENBLAS-THREADS", id = 0L)$id
stopifnot(id >= 0L, .C("rfb_switch", id = id, ret = 0L)$ret == 0L)
set.seed(1)
B <- matrix(rnorm(500^2), 500)
S <- crossprod(B) + diag(500)
invisible(chol(S))
invisible(solve(S, rnorm(500)))

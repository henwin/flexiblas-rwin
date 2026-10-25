## Are results bit for bit those of R's own BLAS and LAPACK?
##   Rscript test-identical.R ref    with R's own Rblas.dll/Rlapack.dll: saves
##                                   identical-ref.rds
##   Rscript test-identical.R cmp    with FlexiBLAS: compares the current
##                                   backend (default NETLIB) with identical()
## FlexiBLAS's NETLIB backend and LAPACK fallback are compiled from the same
## reference sources as R's; this checks that the compilation, too, gives
## the same bits.
mode <- commandArgs(TRUE)[1]
options(matprod = "blas")
set.seed(1)
n <- 300L
A <- matrix(rnorm(n * n), n)
S <- crossprod(A) + diag(n)
b <- rnorm(n)
Z <- matrix(complex(real = rnorm(n * n), imaginary = rnorm(n * n)), n)
H <- crossprod(Z) + diag(n)
v <- rnorm(n)

run <- function() list(
    dgemm      = A %*% A,
    dgemv      = A %*% v,
    dsyrk      = crossprod(A),
    dtcrossprod = tcrossprod(A),
    zgemm      = Z %*% Z,
    zherk      = crossprod(Conj(Z), Z),
    dgesv      = solve(A, b),
    dgetri     = solve(A),
    dpotrf     = chol(S),
    dpotri     = chol2inv(chol(S)),
    dgeqp3     = qr.R(qr(A, LAPACK = TRUE)),
    dsyevr     = eigen(S, symmetric = TRUE),
    dgeev      = eigen(A, only.values = TRUE)$values,
    dgesdd     = svd(A),
    det        = determinant(A),
    norm1      = norm(A, "1"),
    rcond      = rcond(A),
    zgesv      = solve(H, Z[, 1]),
    zheev      = eigen(H, symmetric = TRUE)$values,
    zgesdd     = svd(Z)$d
)

if (identical(mode, "ref")) {
    saveRDS(run(), "identical-ref.rds")
    cat("saved", length(run()), "results from R's own BLAS and LAPACK\n")
    quit(status = 0)
}

ref <- readRDS("identical-ref.rds")
res <- run()
cur <- if (requireNamespace("flexiblas", quietly = TRUE)) flexiblas::flexiblas_current_backend() else "?"
cat("backend:", cur, "\n")
diffs <- 0L
for (k in names(ref)) {
    same <- identical(res[[k]], ref[[k]])
    num <- function(x) unlist(lapply(if (is.list(x)) x else list(x), function(y) as.complex(unlist(y))))
    d <- if (same) 0 else max(Mod(num(res[[k]]) - num(ref[[k]])), na.rm = TRUE)
    cat(sprintf("%-12s %s\n", k, if (same) "identical" else sprintf("differs (max abs diff %.2e)", d)))
    diffs <- diffs + !same
}
cat(diffs, "of", length(ref), "results differ from R's own\n")
quit(status = as.integer(diffs > 0))

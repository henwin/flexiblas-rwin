## Are results bit for bit those of R's own BLAS and LAPACK?
##   Rscript test-identical.R ref    with R's own Rblas.dll/Rlapack.dll: saves
##                                   identical-ref.rds
##   Rscript test-identical.R cmp    with FlexiBLAS: compares the current
##                                   backend (default NETLIB) bit for bit
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
H <- crossprod(Conj(Z), Z) + diag(n)   # Hermitian: crossprod() does not conjugate
v <- rnorm(n)

run <- function() list(
    dgemm      = A %*% A,
    dgemv      = A %*% v,
    dsyrk      = crossprod(A),
    dtcrossprod = tcrossprod(A),
    zgemm      = Z %*% Z,
    zgemm_cp   = crossprod(Conj(Z), Z),   # R's complex crossprod() calls zgemm
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

## Timings on the same runner, for the effect of the compiler flags.
B <- matrix(rnorm(1500^2), 1500)
SB <- crossprod(B) + diag(1500)
timings <- function() c(
    "dgemm, n = 1500"  = system.time(B %*% B)[["elapsed"]],
    "dpotrf, n = 1500" = system.time(chol(SB))[["elapsed"]],
    "dgesv, n = 1500"  = system.time(solve(B, B[, 1]))[["elapsed"]],
    "dsyevr, n = 1500" = system.time(eigen(SB, symmetric = TRUE))[["elapsed"]],
    ## many small calls, where FlexiBLAS's dispatch would show
    "1e5 x dgemm, n = 10" = system.time(for (i in 1:1e5) a10 %*% a10)[["elapsed"]],
    "1e5 x dgesv, n = 10" = system.time(for (i in 1:1e5) solve(a10, b10))[["elapsed"]])
a10 <- matrix(rnorm(100), 10)
b10 <- rnorm(10)

if (identical(mode, "ref")) {
    saveRDS(list(results = run(), timings = timings()), "identical-ref.rds")
    cat("saved", length(run()), "results and timings from R's own BLAS and LAPACK\n")
    quit(status = 0)
}

saved <- readRDS("identical-ref.rds")
ref <- saved$results
res <- run()
cur <- if (requireNamespace("flexiblas", quietly = TRUE)) flexiblas::flexiblas_current_backend() else "?"
cat("backend:", cur, "\n")
diffs <- 0L
for (k in names(ref)) {
    ## identical()'s defaults equate 0 and -0 and all NaN payloads
    same <- identical(res[[k]], ref[[k]], num.eq = FALSE, single.NA = FALSE)
    num <- function(x) unlist(lapply(if (is.list(x)) x else list(x), function(y) as.complex(unlist(y))))
    d <- if (same) 0 else max(Mod(num(res[[k]]) - num(ref[[k]])), na.rm = TRUE)
    cat(sprintf("%-12s %s\n", k, if (same) "identical" else sprintf("differs (max abs diff %.2e)", d)))
    diffs <- diffs + !same
}
cat(diffs, "of", length(ref), "results differ from R's own\n\n")
t1 <- timings()
cat(sprintf("%-20s %8s %8s\n", "elapsed (s)", "R's own", cur))
for (k in names(t1)) cat(sprintf("%-20s %8.2f %8.2f\n", k, saved$timings[[k]], t1[[k]]))
quit(status = as.integer(diffs > 0))

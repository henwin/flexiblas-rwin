## Are results bit for bit those of R's own BLAS and LAPACK?
##   Rscript test-identical.R ref    with R's own Rblas.dll/Rlapack.dll: saves
##                                   identical-ref.rds
##   Rscript test-identical.R cmp    with FlexiBLAS: compares the current
##                                   backend (default NETLIB) bit for bit
## Several sizes and seeds, 21 operations each.
## FlexiBLAS's NETLIB backend and LAPACK fallback are compiled from the same
## reference sources as R's; this checks that the compilation, too, gives
## the same bits.
mode <- commandArgs(TRUE)[1]
options(matprod = "blas")
## sizes around the block and threshold boundaries of the NA test (65, 129,
## 385, 1000) and small ones; two seeds except for the largest
cases <- rbind(expand.grid(n = c(3L, 33L, 65L, 129L, 300L, 385L), seed = 1:2),
               data.frame(n = 1000L, seed = 1L))

run <- function(n, seed) {
    set.seed(seed)
    A <- matrix(rnorm(n * n), n)
    S <- crossprod(A) + diag(n)
    b <- rnorm(n)
    Z <- matrix(complex(real = rnorm(n * n), imaginary = rnorm(n * n)), n)
    H <- crossprod(Conj(Z), Z) + diag(n)   # Hermitian: crossprod() does not conjugate
    v <- rnorm(n)
    m <- n %/% 2 + 1
    list(
    dgemm      = A %*% A,
    dgemm_rect = A[1:m, , drop = FALSE] %*% A[, 1:m, drop = FALSE],
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
}
runall <- function() lapply(seq_len(nrow(cases)), function(i) run(cases$n[i], cases$seed[i]))

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
    saveRDS(list(results = runall(), timings = timings()), "identical-ref.rds")
    cat("saved", nrow(cases), "cases of", length(run(3L, 1L)), "results and timings from R's own BLAS and LAPACK\n")
    quit(status = 0)
}

saved <- readRDS("identical-ref.rds")
ref <- saved$results
res <- runall()
cur <- if (requireNamespace("flexiblas", quietly = TRUE)) flexiblas::flexiblas_current_backend() else "?"
cat("backend:", cur, "\n")
num <- function(x) unlist(lapply(if (is.list(x)) x else list(x), function(y) as.complex(unlist(y))))
diffs <- 0L
for (i in seq_len(nrow(cases))) {
    bad <- character()
    for (k in names(ref[[i]])) {
        ## identical()'s defaults equate 0 and -0 and all NaN payloads
        if (identical(res[[i]][[k]], ref[[i]][[k]], num.eq = FALSE, single.NA = FALSE)) next
        d <- max(Mod(num(res[[i]][[k]]) - num(ref[[i]][[k]])), na.rm = TRUE)
        bad <- c(bad, sprintf("%s (max abs diff %.2e)", k, d))
    }
    diffs <- diffs + length(bad)
    cat(sprintf("n = %4d, seed %d: %s\n", cases$n[i], cases$seed[i],
                if (length(bad)) paste(bad, collapse = ", ") else "all identical"))
}
cat(diffs, "of", nrow(cases) * length(ref[[1]]), "results differ from R's own\n\n")
t1 <- timings()
cat(sprintf("%-20s %8s %8s\n", "elapsed (s)", "R's own", cur))
for (k in names(t1)) cat(sprintf("%-20s %8.2f %8.2f\n", k, saved$timings[[k]], t1[[k]]))
quit(status = as.integer(diffs > 0))

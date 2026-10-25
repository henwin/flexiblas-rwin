## Results and timings of R's BLAS and LAPACK uses, for comparing builds of
## Rblas.dll and Rlapack.dll with different compiler flags.
##   Rscript test-flags.R ref          saves the results to flags-ref.rds
##   Rscript test-flags.R cmp LABEL    compares with them, bit for bit
## Both print timings, the median of five runs, as "LABEL op seconds".
args <- commandArgs(TRUE)
mode <- args[1]
label <- if (length(args) > 1) args[2] else mode

rnd <- function(n, m = n, cx = FALSE) {
    x <- matrix(rnorm(n * m), n, m)
    if (cx) x + 1i * matrix(rnorm(n * m), n, m) else x
}
spd <- function(n) crossprod(rnd(n)) + diag(n)
hpd <- function(n) { z <- rnd(n, cx = TRUE); crossprod(Conj(z), z) + diag(n) }

## Every entry point R itself has into LAPACK (src/modules/lapack/Lapack.c)
## and the BLAS behind %*%, crossprod and backsolve, at sizes on both sides
## of LAPACK's block size.
results <- function() {
    out <- list()
    for (n in c(1, 3, 17, 64, 200)) {
        set.seed(n)
        A <- rnd(n); B <- rnd(n, 7); S <- spd(n); v <- rnorm(n)
        Z <- rnd(n, cx = TRUE); H <- hpd(n); W <- rnd(n, 7, cx = TRUE)
        R <- chol(S)
        o <- list(
            gemm = A %*% B, gemv = A %*% v, syrk = crossprod(A), tcp = tcrossprod(A),
            trsm = backsolve(R, B), trsm_t = backsolve(R, B, transpose = TRUE), fsolve = forwardsolve(t(R), B),
            zgemm = Z %*% W, zherk = crossprod(Conj(Z), Z),
            solve = solve(A, B), inverse = solve(A), zsolve = solve(Z, W),
            chol = chol(S), chol2inv = chol2inv(R), pivot = chol(S, pivot = TRUE),
            qr_linpack = qr(A)$qr, qr_lapack = qr(A, LAPACK = TRUE)$qr,
            qr_coef = qr.coef(qr(A, LAPACK = TRUE), B), qr_qy = qr.qy(qr(A, LAPACK = TRUE), B),
            zqr = qr(Z)$qr, zqr_coef = qr.coef(qr(Z), W), zqr_qy = qr.qy(qr(Z), W),
            eigen_sym = eigen(S), eigen_sym_val = eigen(S, only.values = TRUE)$values,
            eigen_gen = eigen(A), eigen_herm = eigen(H), eigen_zgen = eigen(Z),
            svd = svd(A), svd_d = svd(A, 0, 0)$d, la_svd = La.svd(A), zsvd = svd(Z),
            det = determinant(A), zdet_solve = solve(Z) %*% Z,
            norm = sapply(c("O", "I", "F", "M", "2"), function(t) norm(A, t)),
            rcond = c(rcond(A), rcond(A, "I"), rcond(R, triangular = TRUE), rcond(Z), rcond(Z, triangular = TRUE)),
            kappa = kappa(A, exact = TRUE)
        )
        names(o) <- paste0(names(o), " n=", n)
        out <- c(out, o)
    }
    out
}

## Timings: BLAS-bound operations, LAPACK-bound ones, and many small calls
timings <- function() {
    set.seed(1)
    A <- rnd(1000); B <- rnd(1000); S <- spd(1000); R <- chol(S); v <- rnorm(1000)
    E <- spd(400); G <- rnd(400); Z <- rnd(400, cx = TRUE); a <- rnd(10); b <- rnd(10)
    ops <- list(
        "dgemm n=1000"         = function() A %*% B,
        "dsyrk n=1000"         = function() crossprod(A),
        "dgemv n=1000 x200"    = function() for (i in 1:200) A %*% v,
        "dtrsm n=1000"         = function() backsolve(R, B),
        "dgemm n=10 x1e5"      = function() for (i in 1:1e5) a %*% b,
        "LINPACK qr n=1000"    = function() qr(A),
        "solve n=1000"         = function() solve(A, B),
        "chol n=1000"          = function() chol(S),
        "eigen sym n=400"      = function() eigen(E),
        "eigen gen n=400"      = function() eigen(G),
        "svd n=400"            = function() svd(G),
        "zgemm n=400"          = function() Z %*% Z,
        "eigen zgen n=400"     = function() eigen(Z)
    )
    for (nm in names(ops)) {
        t <- median(replicate(5, system.time(ops[[nm]]())[["elapsed"]]))
        cat(sprintf("%s|%s|%.3f\n", label, nm, t))
    }
}

res <- results()
if (mode == "ref") {
    saveRDS(res, "flags-ref.rds")
} else {
    ref <- readRDS("flags-ref.rds")
    same <- mapply(identical, res, ref[names(res)])
    ops <- unique(sub(" n=.*", "", names(res)))
    diff_ops <- unique(sub(" n=.*", "", names(res)[!same]))
    cat(sprintf("%s: %d of %d results differ from R's; operations: %s\n", label, sum(!same), length(same),
                if (length(diff_ops)) paste(diff_ops, collapse = ", ") else "none"))
}
timings()

## How NA, NaN and Inf propagate through BLAS and LAPACK.
##
## R's NA_real_ is a NaN whose low word is 1954 (src/main/arithmetic.c).
## IEEE arithmetic returns *a* NaN when an operand is NaN; which payload
## survives depends on the instruction and the operand order, so whether NA
## comes out as NA or as a plain NaN is up to the kernel and the hardware.
## R's reference BLAS is also patched so that x * 0 is not short-cut to 0
## when x is Inf or NaN (src/extra/blas/README).
##
##   Rscript test-nan.R ref    with R's own Rblas.dll/Rlapack.dll (Windows)
##   Rscript test-nan.R cmp    for every FlexiBLAS backend, compared with
##                             nan-ref.rds when it exists
## Differences are reported, not treated as failures.

mode <- commandArgs(TRUE)[1]

## Non-finite values placed where the other operand is zero, which is where
## a BLAS that skips zero multiplications loses them; n = 4 exercises the
## small-matrix paths, n = 500 the optimised level-3 kernels.
cases <- function(n) {
    set.seed(42)
    k <- if (n > 10) 6L else 1L
    pos <- cbind(sample(n, k), sample(n, k))      # (row, col) in A
    Z <- matrix(rnorm(n * n), n); Z[pos[, 2], ] <- 0
    put <- function(v) { A <- matrix(rnorm(n * n), n); A[pos] <- v; A }
    A_nan <- put(NaN); A_na <- put(NA); A_inf <- put(Inf)
    A_mix <- put(c(NA, NaN, Inf, -Inf, NA, NaN)[seq_len(k)])
    v0 <- rnorm(n); v0[pos[, 2]] <- 0
    S <- crossprod(matrix(rnorm(n * n), n)) + diag(n); S[3, 3] <- NaN
    Asol <- diag(n) + 0.01; Asol[2, 1] <- NaN
    prods <- function() list(
        "dgemm NaN"    = A_nan %*% Z,
        "dgemm NA"     = A_na %*% Z,
        "dgemm Inf"    = A_inf %*% Z,
        "dgemm mixed"  = A_mix %*% Z,
        "dgemm t(A) B" = crossprod(t(A_na), Z),
        "dgemm A t(B)" = tcrossprod(A_na, t(Z)),
        "dgemv NA"     = A_na %*% v0,
        "dgemv Inf"    = A_inf %*% v0,
        "dsyrk NA"     = crossprod(A_na),
        "zgemm NA"     = (A_na + 0i) %*% (Z + 0i)
    )
    attempt <- function(expr)
        tryCatch(expr, error = function(e) paste("error:", conditionMessage(e)))
    old <- options(matprod = "blas"); on.exit(options(old))
    blas <- prods()
    options(matprod = "default")
    dflt <- prods()
    res <- c(setNames(blas, paste(names(blas), "[blas]")),
             setNames(dflt, paste(names(dflt), "[default]")),
             list("dgesv NaN"  = attempt(solve(Asol, rep(1, n))),
                  "dpotrf NaN" = attempt(chol(S)),
                  "dgeev NaN"  = attempt(eigen(Asol, only.values = TRUE)$values)))
    setNames(res, paste0("n=", n, " ", names(res)))
}

## Compact signature: counts of NA (not NaN), NaN and Inf entries, plus a
## hash of the pattern (0 finite, 1 NA, 2 NaN, 3 Inf, 4 -Inf), so that equal
## signatures mean equal patterns.
signature <- function(x) {
    if (is.character(x)) return(substr(x, 1, 40))
    x <- as.vector(x)
    if (is.complex(x)) x <- c(Re(x), Im(x))
    k <- integer(length(x))
    k[is.na(x) & !is.nan(x)] <- 1L; k[is.nan(x)] <- 2L
    k[x == Inf & !is.na(x)] <- 3L; k[x == -Inf & !is.na(x)] <- 4L
    f <- tempfile(); writeBin(k, f); on.exit(unlink(f))
    sprintf("A%d N%d I%d #%s", sum(k == 1L), sum(k == 2L), sum(k >= 3L), unname(tools::md5sum(f)))
}
run <- function() lapply(c(cases(4), cases(500)), signature)

if (identical(mode, "ref")) {
    res <- run()
    saveRDS(res, "nan-ref.rds")
    for (k in names(res)) cat(sprintf("%-30s %s\n", k, res[[k]]))
    quit(status = 0)
}

## Backend switching through the flexiblas package, where R's BLAS is FlexiBLAS.
if (requireNamespace("flexiblas", quietly = TRUE) && flexiblas::flexiblas_avail()) {
    backends <- setdiff(flexiblas::flexiblas_list(), "__FALLBACK__")
    use <- function(be) flexiblas::flexiblas_switch(flexiblas::flexiblas_load_backend(be))
} else {
    ## No FlexiBLAS: compare whatever BLAS R uses now, e.g. after swapping
    ## libRblas on macOS, with the saved reference.
    backends <- "current BLAS"
    use <- function(be) invisible()
}
cat(R.version.string, "on", R.version$platform, "\n")
cat("CPU:", Sys.info()[["machine"]], "\n")
cat("BLAS:", extSoftVersion()[["BLAS"]], "\nLAPACK:", La_library(), "\n\n")

res <- list()
for (be in backends) { use(be); res[[be]] <- run() }
ref <- if (file.exists("nan-ref.rds")) readRDS("nan-ref.rds") else res[[1]]
refname <- if (file.exists("nan-ref.rds")) "R's own" else backends[1]

cat("Signature: A = NA, N = NaN, I = Inf counts, # = position checksum.\n")
cat("Columns show 'same' when equal to", refname, "\n\n")
w <- max(nchar(names(ref)))
cat(formatC("", width = -w), " ", formatC(refname, width = -30),
    paste(formatC(backends, width = -18), collapse = " "), "\n", sep = "")
ndiff <- 0
for (k in names(ref)) {
    cells <- vapply(backends, function(be)
        if (identical(res[[be]][[k]], ref[[k]])) "same" else res[[be]][[k]], "")
    ndiff <- ndiff + any(cells != "same")
    cat(formatC(k, width = -w), " ", formatC(ref[[k]], width = -30),
        paste(formatC(cells, width = -18), collapse = " "), "\n", sep = "")
}
cat(sprintf("\n%d of %d results differ from %s for at least one backend\n",
            ndiff, length(ref), refname))

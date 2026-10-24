## How NA, NaN and Inf propagate through BLAS and LAPACK.
##
## R's reference BLAS is patched so that x * 0 is not short-cut to 0 when x
## is Inf or NaN (src/extra/blas/README). Optimised BLAS need not do this.
## Run first with R's own Rblas.dll/Rlapack.dll:   Rscript test-nan.R ref
## then with the FlexiBLAS forwarders:              Rscript test-nan.R flexiblas
## The second run compares every backend with the saved reference. It reports
## differences but does not fail on them: they are findings, not errors.

mode <- commandArgs(TRUE)[1]

## Each case puts a non-finite value where the other operand is zero, which
## is exactly where a BLAS that skips zero multiplications loses it.
cases <- function() {
    n <- 4
    Z <- matrix(1, n, n); Z[1, ] <- 0          # zero first row
    A_nan <- matrix(1, n, n); A_nan[2, 1] <- NaN
    A_na  <- matrix(1, n, n); A_na[2, 1]  <- NA
    A_inf <- matrix(1, n, n); A_inf[2, 1] <- Inf
    v0 <- c(0, 1, 1, 1)
    Zc <- Z + 0i; Ac <- A_nan + 0i
    S <- crossprod(matrix(1:16, 4)) + diag(4); S[3, 3] <- NaN
    b <- c(1, 2, 3, 4); Asol <- diag(4); Asol[2, 1] <- NaN
    prods <- function() list(
        "dgemm NaN"        = A_nan %*% Z,
        "dgemm NA"         = A_na %*% Z,
        "dgemm Inf"        = A_inf %*% Z,
        "dgemm t(A) B"     = crossprod(t(A_nan), Z),
        "dgemm A t(B)"     = tcrossprod(A_nan, t(Z)),
        "dgemv NaN"        = A_nan %*% v0,
        "dgemv Inf"        = A_inf %*% v0,
        "dsyrk NaN"        = crossprod(A_nan),
        "zgemm NaN"        = Ac %*% Zc
    )
    attempt <- function(expr) tryCatch(expr, error = function(e) paste("error:", conditionMessage(e)))
    old <- options(matprod = "blas"); on.exit(options(old))
    blas <- prods()
    options(matprod = "default")
    dflt <- prods()
    names(blas) <- paste(names(blas), "[blas]")
    names(dflt) <- paste(names(dflt), "[default]")
    c(blas, dflt, list(
        "dgesv NaN"  = attempt(solve(Asol, b)),
        "dpotrf NaN" = attempt(chol(S)),
        "dgeev NaN"  = attempt(eigen(Asol, only.values = TRUE)$values)
    ))
}

## A result's signature: which entries are NA (but not NaN), NaN, +-Inf.
signature <- function(x) {
    if (is.character(x)) return(x)
    x <- as.vector(x)
    if (is.complex(x)) x <- c(Re(x), Im(x))
    paste0(ifelse(is.na(x) & !is.nan(x), "A",
           ifelse(is.nan(x), "N",
           ifelse(is.infinite(x), "I", "."))), collapse = "")
}

if (identical(mode, "ref")) {
    res <- lapply(cases(), signature)
    saveRDS(res, "nan-ref.rds")
    for (k in names(res)) cat(sprintf("%-26s %s\n", k, res[[k]]))
    quit(status = 0)
}

ref <- readRDS("nan-ref.rds")
dyn.load(file.path(R.home("bin"), "rfbtest.dll"))
backends <- c("NETLIB", "OPENBLAS-THREADS", "OPENBLAS-OPENMP")
out <- matrix("", length(ref), length(backends) + 1,
              dimnames = list(names(ref), c("R", backends)))
out[, "R"] <- unlist(ref)
for (be in backends) {
    id <- .C("rfb_load", name = be, id = 0L)$id
    stopifnot(id >= 0L, .C("rfb_switch", id = id, ret = 0L)$ret == 0L)
    res <- lapply(cases(), signature)
    out[, be] <- ifelse(unlist(res) == unlist(ref), "same", unlist(res))
}
cat("Signature per result, column-major: . finite, A NA, N NaN, I Inf.\n")
cat("'same' means identical to R's own BLAS/LAPACK.\n\n")
w <- max(nchar(rownames(out)))
for (i in seq_len(nrow(out)))
    cat(formatC(rownames(out)[i], width = -w), " ",
        paste(formatC(out[i, ], width = -18), collapse = " "), "\n", sep = "")
cat(sprintf("\n%d of %d results differ from R's own for at least one backend\n",
            sum(apply(out[, backends] != "same", 1, any)), nrow(out)))

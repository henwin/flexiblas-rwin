## Where NA and NaN meet in one result. R's NA is a NaN with payload 1954;
## when an operation combines NA with NaN (or with Inf * 0, Inf - Inf), the
## result is one of them, and which one depends on operand order and the
## processor (?NA: "either might result (which may depend on the R
## platform)"). This records, for R's own BLAS and LAPACK and for R's own
## arithmetic, which elements come out NA, NaN, Inf or finite, on matrices
## with NA, NaN and Inf spread densely, so that platforms can be compared.
##   Rscript test-nan-mixed.R run LABEL      writes nan-mixed-LABEL.txt
##   Rscript test-nan-mixed.R compare FILE...
args <- commandArgs(TRUE)

if (args[1] == "run") {
    label <- args[2]
    options(matprod = "blas")      # products to the BLAS even with NaN
    code <- function(x) {          # 0 finite, 1 NA, 2 NaN, 3 Inf, 4 -Inf
        x <- c(Re(x), if (is.complex(x)) Im(x))
        k <- integer(length(x))
        k[is.na(x) & !is.nan(x)] <- 1L; k[is.nan(x)] <- 2L
        k[x == Inf & !is.na(x)] <- 3L; k[x == -Inf & !is.na(x)] <- 4L
        k
    }
    out <- character()
    rec <- function(op, x) {
        r <- tryCatch(code(x), error = function(e) NULL)
        if (is.null(r)) { out <<- c(out, sprintf("%s|%s|error|||", label, op)); return() }
        f <- tempfile(); writeBin(r, f)
        out <<- c(out, sprintf("%s|%s|%d|%d|%d|%s", label, op, sum(r == 1L), sum(r == 2L),
                               sum(r >= 3L), substr(unname(tools::md5sum(f)), 1, 8)))
    }
    for (n in c(3, 17, 100)) {
        set.seed(n)
        spec <- function(m) {       # about one entry in 20 non-finite
            k <- sample(length(m), max(1, length(m) %/% 20))
            m[k] <- sample(c(NA, NaN, Inf, -Inf), length(k), replace = TRUE)
            m
        }
        A <- spec(matrix(rnorm(n * n), n)); B <- spec(matrix(rnorm(n * n), n)); v <- spec(rnorm(n))
        Z <- A + 1i * spec(matrix(rnorm(n * n), n)); W <- B + 1i * spec(matrix(rnorm(n * n), n))
        U <- matrix(rnorm(n * n), n); U[lower.tri(U)] <- 0; diag(U) <- diag(U) + n; U <- spec(U)
        s <- paste0(" n=", n)
        rec(paste0("dgemm", s), A %*% B)
        rec(paste0("dgemv", s), A %*% v)
        rec(paste0("dsyrk", s), crossprod(A))
        rec(paste0("dgemm tcp", s), tcrossprod(A, B))
        rec(paste0("dtrsm", s), backsolve(U, B))
        rec(paste0("zgemm", s), Z %*% W)
        rec(paste0("zherk", s), crossprod(Conj(Z), Z))
        rec(paste0("dgesv", s), tryCatch(solve(A, B), error = function(e) NULL))
        rec(paste0("dgeqp3", s), qr(A, LAPACK = TRUE)$qr)
        rec(paste0("LINPACK dqrdc2", s), qr(A)$qr)
        ## R's own arithmetic, no BLAS
        rec(paste0("A + B", s), A + B)
        rec(paste0("A * B", s), A * B)
        rec(paste0("colSums", s), colSums(A))
        rec(paste0("cumsum", s), cumsum(c(A)))
        rec(paste0("matprod internal", s), local({ op <- options(matprod = "internal"); r <- A %*% B; options(op); r }))
    }
    info <- sprintf("%s|platform|%s %s|BLAS %s|LAPACK %s|", label, R.version$platform, R.version.string,
                    extSoftVersion()[["BLAS"]], La_library())
    writeLines(c(info, out), sprintf("nan-mixed-%s.txt", label))
    writeLines(c(info, out))
}

if (args[1] == "compare") {
    l <- unlist(lapply(args[-1], readLines))
    d <- do.call(rbind, strsplit(l, "|", fixed = TRUE))
    info <- d[d[, 2] == "platform", , drop = FALSE]
    cat(sprintf("%-14s %s\n", info[, 1], apply(info[, 3:5, drop = FALSE], 1, paste, collapse = "; ")), sep = "")
    d <- d[d[, 2] != "platform", , drop = FALSE]
    cell <- ifelse(d[, 3] == "error", "error", sprintf("%s/%s/%s %s", d[, 3], d[, 4], d[, 5], d[, 6]))
    t <- tapply(cell, list(factor(d[, 2], unique(d[, 2])), factor(d[, 1], unique(d[, 1]))), identity)
    ## a row whose platforms do not all agree
    differ <- apply(t, 1, function(r) length(unique(r)) > 1)
    cat(sprintf("\n%d of %d results differ between platforms (NA/NaN/Inf counts and pattern hash):\n",
                sum(differ), nrow(t)))
    options(width = 200)
    print(noquote(t[differ, , drop = FALSE]))
}

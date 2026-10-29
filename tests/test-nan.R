## How NA, NaN and Inf come out of BLAS and LAPACK.
##
## R's NA_real_ is a NaN whose low word is 1954 (src/main/arithmetic.c).
## IEEE arithmetic returns *a* NaN when an operand is NaN; which payload
## survives depends on the instruction and the operand order, so whether NA
## comes out as NA or as a plain NaN is up to the kernel and the hardware
## (?NA: "either might result (which may depend on the R platform)"). R's
## reference BLAS is also patched so that x * 0 is not short-cut to 0 when
## x is Inf or NaN (src/extra/blas/README).
##
## Two modes, which differ in what is compared and where the non-finite
## values are put:
##
##   propagate   BLAS backends against R's own BLAS and LAPACK, on one
##               machine. Non-finite values are placed where the other
##               operand is zero, which is where a BLAS that skips zero
##               multiplications loses them.
##     Rscript test-nan.R propagate ref   with R's own Rblas.dll/Rlapack.dll
##     Rscript test-nan.R propagate cmp   every FlexiBLAS backend (or the
##                                        current BLAS), against nan-ref.rds
##                                        when it exists
##   pattern     platforms against each other, with R's own BLAS, LAPACK and
##               arithmetic. NA, NaN and Inf are spread at random, so that
##               NA meets NaN in one result and the platforms show which of
##               the two they keep.
##     Rscript test-nan.R pattern run LABEL       writes nan-pattern-LABEL.txt
##     Rscript test-nan.R pattern compare FILE...
##
## The sizes come from the code paths of OpenBLAS 0.3.34 as built for
## Rtools (DYNAMIC_ARCH, OpenMP), of reference LAPACK and of the compiled
## reference BLAS. In propagate mode each routine gets one
## size per regime of its own: below every threshold, the first size with
## more than one thread, the first without the SkylakeX small-matrix
## kernel, the first with a split packing block in each kernel set, and a
## size with every mechanism at once. In pattern mode every operation runs
## over n = 1..64, which covers the loop remainders of the compiled
## reference BLAS and of OpenBLAS's unrolling, and over the level-3
## boundaries of the Rtools build.
## Differences are reported, not treated as failures.

args <- commandArgs(TRUE)
mode <- args[1]; what <- args[2]

## 0 finite, 1 NA, 2 NaN, 3 Inf, 4 -Inf, on the real and imaginary parts
code <- function(x) {
    x <- as.vector(x)
    x <- c(Re(x), if (is.complex(x)) Im(x))
    k <- integer(length(x))
    k[is.na(x) & !is.nan(x)] <- 1L; k[is.nan(x)] <- 2L
    k[x == Inf & !is.na(x)] <- 3L; k[x == -Inf & !is.na(x)] <- 4L
    k
}
## Counts of NA (not NaN), NaN and Inf entries and a hash of the pattern,
## so that equal signatures mean equal patterns.
signature <- function(x) {
    if (is.character(x)) return(substr(x, 1, 40))
    k <- code(x)
    f <- tempfile(); writeBin(k, f); on.exit(unlink(f))
    sprintf("A%d N%d I%d #%s", sum(k == 1L), sum(k == 2L), sum(k >= 3L), unname(tools::md5sum(f)))
}
attempt <- function(expr)
    tryCatch(expr, error = function(e) paste("error:", conditionMessage(e)))

cpu <- function() {
    s <- Sys.info()[["sysname"]]
    x <- if (s == "Linux") {
        l <- grep("^(model name|Model|Hardware)", readLines("/proc/cpuinfo"), value = TRUE)
        if (length(l)) sub("^[^:]*: *", "", l[1]) else ""
    } else if (s == "Darwin") system("sysctl -n machdep.cpu.brand_string", intern = TRUE)
    else Sys.getenv("PROCESSOR_IDENTIFIER")
    sprintf("%s (%s, %d cores)", if (nzchar(x)) x else "unknown", Sys.info()[["machine"]], parallel::detectCores())
}
info <- function() {
    cat(R.version.string, "on", R.version$platform, "\n")
    cat("CPU:", cpu(), "\n")
    cat("BLAS:", extSoftVersion()[["BLAS"]], "\nLAPACK:", La_library(), "\n")
}
## Which kernel set OpenBLAS picked ("Core: ...") goes to stderr at load.
Sys.setenv(OPENBLAS_VERBOSE = 2)

## ----- propagate --------------------------------------------------------

sizes <- list(dgemm = c(3, 65, 101, 129, 193, 385, 1000),
              dgemv = c(3, 679),
              dsyrk = c(3, 77, 129, 193, 385, 1000),
              zgemm = c(3, 33, 129, 193, 257, 1000),
              lapack = c(3, 33, 65, 129, 385, 1000))

## The operands for order n: non-finite values at k positions of A, and
## zeros in the matching rows of the other operand.
operands <- function(n) {
    set.seed(n)
    k <- if (n > 10) 6L else 1L
    pos <- cbind(sample(n, k), sample(n, k))      # (row, col) in A
    Z <- matrix(rnorm(n * n), n); Z[pos[, 2], ] <- 0
    put <- function(v) { A <- matrix(rnorm(n * n), n); A[pos] <- v; A }
    v0 <- rnorm(n); v0[pos[, 2]] <- 0
    S <- crossprod(matrix(rnorm(n * n), n)) + diag(n); S[3, 3] <- NaN
    Asol <- diag(n) + 0.01; Asol[2, 1] <- NaN
    list(n = n, Z = Z, v0 = v0, S = S, Asol = Asol, A_nan = put(NaN), A_na = put(NA),
         A_inf = put(Inf), A_mix = put(c(NA, NaN, Inf, -Inf, NA, NaN)[seq_len(k)]))
}
## The products of one routine at one size, under matprod = "blas" and
## under the default, which sends a product with a non-finite value to R's
## own loops.
products <- function(r, o) {
    with(o, switch(r,
        dgemm = list("NaN"    = A_nan %*% Z,
                     "NA"     = A_na %*% Z,
                     "Inf"    = A_inf %*% Z,
                     "mixed"  = A_mix %*% Z,
                     "t(A) B" = crossprod(t(A_na), Z),
                     "A t(B)" = tcrossprod(A_na, t(Z))),
        dgemv = list("NA" = A_na %*% v0, "Inf" = A_inf %*% v0),
        dsyrk = list("NA" = crossprod(A_na)),
        zgemm = list("NA" = (A_na + 0i) %*% (Z + 0i))))
}
propagate <- function() {
    ops <- list()
    data <- function(n) {
        key <- as.character(n)
        if (is.null(ops[[key]])) ops[[key]] <<- operands(n)
        ops[[key]]
    }
    res <- list()
    for (r in c("dgemm", "dgemv", "dsyrk", "zgemm")) for (n in sizes[[r]]) {
        o <- data(n)
        old <- options(matprod = "blas"); blas <- products(r, o)
        options(matprod = "default"); dflt <- products(r, o); options(old)
        res[sprintf("%s %s n=%d [blas]", r, names(blas), n)] <- blas
        res[sprintf("%s %s n=%d [default]", r, names(dflt), n)] <- dflt
    }
    for (n in sizes$lapack) {
        o <- data(n)
        res[[sprintf("dgesv NaN n=%d", n)]]  <- attempt(solve(o$Asol, rep(1, n)))
        res[[sprintf("dpotrf NaN n=%d", n)]] <- attempt(chol(o$S))
        res[[sprintf("dgeev NaN n=%d", n)]]  <- attempt(eigen(o$Asol, only.values = TRUE)$values)
    }
    lapply(res, signature)
}

if (identical(mode, "propagate") && identical(what, "ref")) {
    info()
    res <- propagate()
    saveRDS(res, "nan-ref.rds")
    cat("\n")
    for (k in names(res)) cat(sprintf("%-32s %s\n", k, res[[k]]))
    quit(status = 0)
}

if (identical(mode, "propagate") && identical(what, "cmp")) {
    ## Backend switching through the flexiblas package, where R's BLAS is FlexiBLAS.
    fb <- requireNamespace("flexiblas", quietly = TRUE) && flexiblas::flexiblas_avail()
    if (fb) {
        backends <- setdiff(flexiblas::flexiblas_list(), "__FALLBACK__")
        use <- function(be) flexiblas::flexiblas_switch(flexiblas::flexiblas_load_backend(be))
    } else {
        ## No FlexiBLAS: compare whatever BLAS R uses now, e.g. after swapping
        ## libRblas on macOS, with the saved reference.
        backends <- "current BLAS"
        use <- function(be) invisible()
    }
    info()
    flush(stdout())
    res <- list(); threads <- list()
    for (be in backends) {
        use(be)
        res[[be]] <- propagate()
        if (fb) {
            ## the same product with one thread and with the default count
            t0 <- flexiblas::flexiblas_get_num_threads()
            o <- operands(385); old <- options(matprod = "blas")
            flexiblas::flexiblas_set_num_threads(1L); one <- signature(o$A_na %*% o$Z)
            flexiblas::flexiblas_set_num_threads(t0); all <- signature(o$A_na %*% o$Z)
            options(old)
            threads[[be]] <- sprintf("%-20s %d thread(s): %s; 1 thread: %s", be, t0, all,
                                     if (identical(one, all)) "same" else one)
        }
    }
    ref <- if (file.exists("nan-ref.rds")) readRDS("nan-ref.rds") else res[[1]]
    refname <- if (file.exists("nan-ref.rds")) "R's own" else backends[1]

    cat("\nSignature: A = NA, N = NaN, I = Inf counts, # = MD5 of the NA/NaN/Inf pattern.\n")
    cat("A row with one 'same' has every backend equal to ", refname,
        "; otherwise the columns are\n", paste(backends, collapse = ", "), ", 'same' when equal.\n\n", sep = "")
    w <- max(nchar(names(ref)))
    ndiff <- 0
    for (k in names(ref)) {
        cells <- vapply(backends, function(be)
            if (identical(res[[be]][[k]], ref[[k]])) "same" else res[[be]][[k]], "")
        if (all(cells == "same")) cells <- "same" else ndiff <- ndiff + 1
        cat(formatC(k, width = -w), " ", formatC(ref[[k]], width = -52),
            paste(formatC(cells, width = -52), collapse = " "), "\n", sep = "")
    }
    cat(sprintf("\n%d of %d results differ from %s for at least one backend\n",
                ndiff, length(ref), refname))
    if (length(threads)) {
        cat("\ndgemm NA n=385 [blas] by thread count:\n")
        for (l in threads) cat(l, "\n")
    }
    quit(status = 0)
}

## ----- pattern ----------------------------------------------------------

## 1..64 for the loop remainders; then the boundaries of the Rtools build:
## dgemm threaded from 65, Haswell on Windows splits k from 129, SkylakeX
## splits m from 193 and k from 385, 1000 has every mechanism at once.
psizes <- c(1:64, 65, 129, 193, 385, 1000)

if (identical(mode, "pattern") && identical(what, "run")) {
    label <- args[3]
    options(matprod = "blas")      # products to the BLAS even with NaN
    out <- character()
    rec <- function(op, n, x) {
        r <- tryCatch(code(x), error = function(e) NULL)
        out <<- c(out, if (is.null(r)) sprintf("%s|%s|%d|error|||", label, op, n) else {
            f <- tempfile(); writeBin(r, f)
            sprintf("%s|%s|%d|%d|%d|%d|%s", label, op, n, sum(r == 1L), sum(r == 2L),
                    sum(r >= 3L), unname(tools::md5sum(f)))
        })
    }
    for (n in psizes) {
        set.seed(n)
        spec <- function(m) {       # about one entry in 20 non-finite
            k <- sample(length(m), max(1, length(m) %/% 20))
            m[k] <- sample(c(NA, NaN, Inf, -Inf), length(k), replace = TRUE)
            m
        }
        A <- spec(matrix(rnorm(n * n), n)); B <- spec(matrix(rnorm(n * n), n)); v <- spec(rnorm(n))
        Z <- A + 1i * spec(matrix(rnorm(n * n), n)); W <- B + 1i * spec(matrix(rnorm(n * n), n))
        U <- matrix(rnorm(n * n), n); U[lower.tri(U)] <- 0; diag(U) <- diag(U) + n; U <- spec(U)
        rec("dgemm", n, A %*% B)
        rec("dgemv", n, A %*% v)
        rec("dsyrk", n, crossprod(A))
        rec("dgemm tcp", n, tcrossprod(A, B))
        rec("dtrsm", n, backsolve(U, B))
        rec("zgemm", n, Z %*% W)
        rec("zgemm cp", n, crossprod(Conj(Z), Z))
        rec("dgesv", n, tryCatch(solve(A, B), error = function(e) NULL))
        rec("dgeqp3", n, qr(A, LAPACK = TRUE)$qr)
        rec("LINPACK dqrdc2", n, qr(A)$qr)
        ## R's own arithmetic, no BLAS
        rec("A + B", n, A + B)
        rec("A * B", n, A * B)
        rec("colSums", n, colSums(A))
        rec("cumsum", n, cumsum(c(A)))
        ## R's own loops accumulate in long double, and on x86_64 the x87 unit
        ## handles NaN and Inf in microcode: dense non-finite operands take
        ## minutes at n = 1000
        if (n <= 193)
            rec("matprod internal", n, local({ op <- options(matprod = "internal"); r <- A %*% B; options(op); r }))
    }
    hdr <- sprintf("%s|platform||%s %s; %s|BLAS %s|LAPACK %s|", label, R.version$platform,
                   R.version.string, cpu(), extSoftVersion()[["BLAS"]], La_library())
    writeLines(c(hdr, out), sprintf("nan-pattern-%s.txt", label))
    info()
    cat(sprintf("%d results at %d sizes written\n", length(out), length(psizes)))
}

if (identical(mode, "pattern") && identical(what, "compare")) {
    l <- unlist(lapply(args[-(1:2)], readLines))
    ## seven fields; strsplit() drops the empty ones at the end of a line
    d <- do.call(rbind, lapply(strsplit(l, "|", fixed = TRUE), function(x) c(x, rep("", 7 - length(x)))))
    hdr <- d[d[, 2] == "platform", , drop = FALSE]
    cat(sprintf("%-14s %s\n", hdr[, 1], apply(hdr[, 4:6, drop = FALSE], 1, paste, collapse = "; ")), sep = "")
    d <- d[d[, 2] != "platform", , drop = FALSE]
    labels <- unique(d[, 1]); ops <- unique(d[, 2]); ns <- unique(as.integer(d[, 3]))
    cell <- ifelse(d[, 4] == "error", "error", sprintf("%s/%s/%s %s", d[, 4], d[, 5], d[, 6], d[, 7]))
    t <- tapply(cell, list(factor(d[, 2], ops), factor(as.integer(d[, 3]), ns), factor(d[, 1], labels)), identity)
    cat(sprintf("\nCells are NA/NaN/Inf counts and the pattern hash; %d operations at %d sizes (n = %s).\n",
                length(ops), length(ns), paste(range(ns), collapse = "..")))
    cat("Per operation, the sizes on which the platforms do not all agree, then the cells\nat the first of them.\n\n")
    nd <- 0
    for (op in ops) {
        m <- t[op, , , drop = TRUE]
        has <- apply(m, 1, function(r) !all(is.na(r)))      # sizes this operation ran at
        differ <- has & apply(m, 1, function(r) length(unique(r)) > 1)
        if (!any(differ)) { cat(sprintf("%-18s same on all %d sizes\n", op, sum(has))); next }
        nd <- nd + 1
        at <- ns[differ]
        cat(sprintf("%-18s differ on %d of %d sizes: n = %s%s\n", op, length(at), sum(has),
                    paste(head(at, 12), collapse = ", "), if (length(at) > 12) ", ..." else ""))
        for (n in head(at, 2)) {
            cells <- t[op, as.character(n), ]
            cat(sprintf("  n=%-5d %s\n", n, paste(sprintf("%s: %s", labels, cells), collapse = "  ")))
        }
    }
    cat(sprintf("\n%d of %d operations differ between platforms on some size\n", nd, length(ops)))
}

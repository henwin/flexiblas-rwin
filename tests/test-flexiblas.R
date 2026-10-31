## Runs in an R whose Rblas.dll forwards to libflexiblas.dll, with the
## flexiblas package installed. Checks that R's BLAS goes through FlexiBLAS,
## that results agree across backends, and that backend and thread count can
## be changed at runtime.
library(flexiblas)

check <- function(ok, what) {
    cat(sprintf("%-55s %s\n", what, if (ok) "ok" else "FAILED"))
    if (!ok) failures <<- c(failures, what)
}
failures <- character()

check(isTRUE(flexiblas_avail()), "R's BLAS is FlexiBLAS")
cat("FlexiBLAS", format(flexiblas_version()), "\n")
cat("configured backends:", paste(flexiblas_list(), collapse = ", "), "\n")
cat("initial backend:", flexiblas_current_backend(), "\n")

## Workload touching BLAS level 3, LAPACK via Rlapack.dll and complex BLAS.
set.seed(1)
n <- 600L
A <- crossprod(matrix(rnorm(n * n), n)) + diag(n)
b <- rnorm(n)
Z <- matrix(complex(real = rnorm(n * n), imaginary = rnorm(n * n)), n)
work <- function() list(
    prod  = A %*% A,
    solve = solve(A, b),
    chol  = chol(A),
    eigen = eigen(A, symmetric = TRUE, only.values = TRUE)$values,
    qr    = qr.R(qr(A, LAPACK = TRUE))[cbind(1:n, 1:n)],
    cprod = Z %*% Z
)
ref <- work()

cat(sprintf("cores: %d logical, %d physical; OMP_NUM_THREADS=%s\n",
            parallel::detectCores(), parallel::detectCores(logical = FALSE),
            Sys.getenv("OMP_NUM_THREADS", "(unset)")))
B <- matrix(rnorm(3000^2), 3000)
S <- crossprod(B) + diag(3000)
timing <- function(what, expr, label)
    cat(sprintf("  %-8s n = 3000, %s: elapsed %.3fs\n", what, label,
                system.time(expr)[["elapsed"]]))

for (be in grep("^OPENBLAS", flexiblas_list(), value = TRUE)) {
    cat("\n==", be, "==\n")
    id <- flexiblas_load_backend(be)
    flexiblas_switch(id)
    check(flexiblas_current_backend() == be, sprintf("switch to %s", be))

    res <- work()
    for (k in names(ref)) {
        err <- max(Mod(res[[k]] - ref[[k]])) / max(Mod(ref[[k]]))
        check(err < 1e-10, sprintf("%s agrees with NETLIB (rel err %.1e)", k, abs(err)))
    }

    ## flexiblas_get_num_threads() asks the backend, so a count reset inside
    ## OpenBLAS during a product shows up here.
    for (k in unique(c(1L, 2L, max(2L, parallel::detectCores())))) {
        flexiblas_set_num_threads(k)
        timing("B %*% B", B %*% B, sprintf("%d thread(s)", k))
        timing("chol(S)", chol(S), sprintf("%d thread(s)", k))
        ## An explicit count is capped at the 64 threads the bundle's
        ## OpenBLAS is built for (NUM_THREADS) and, in the OpenMP build,
        ## at OMP_THREAD_LIMIT, which is read by libgomp: the pthreads build
        ## has no OpenMP runtime and is outside that variable, as on Linux;
        ## its caps are OPENBLAS_NUM_THREADS and OMP_NUM_THREADS.
        limit <- if (grepl("OPENMP", be)) as.integer(Sys.getenv("OMP_THREAD_LIMIT", k)) else k
        check(flexiblas_get_num_threads() == min(k, 64L, limit),
              sprintf("  %d thread(s) after the products (reports %d)", k,
                      flexiblas_get_num_threads()))
    }
}

cat("\n")
flexiblas_switch(flexiblas_load_backend("NETLIB"))
check(flexiblas_current_backend() == "NETLIB", "switch back to NETLIB")
timing("B %*% B", B %*% B, "NETLIB")
check(isTRUE(all.equal(work()$prod, ref$prod)), "results after switching back")

cat("\n")
if (length(failures)) {
    cat("FAILURES:\n", paste0("  ", failures, "\n"), sep = "")
    quit(status = 1)
}
cat("all checks passed\n")

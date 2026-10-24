## Runs in an R whose Rblas.dll forwards to libflexiblas.dll.
## Checks that R's BLAS goes through FlexiBLAS, that results agree across
## backends, and that backend and thread count can be changed at runtime.

bin <- file.path(R.home("bin"))
dyn.load(file.path(bin, "rfbtest.dll"))

check <- function(ok, what) {
    cat(sprintf("%-55s %s\n", what, if (ok) "ok" else "FAILED"))
    if (!ok) failures <<- c(failures, what)
}
failures <- character()

current <- function()
    trimws(.C("rfb_current", name = strrep(" ", 128))$name)
threads <- function()
    .C("rfb_get_threads", n = 0L)$n
switch_to <- function(id)
    .C("rfb_switch", id = as.integer(id), ret = 0L)$ret

check(.C("rfb_loaded", ok = 0L)$ok == 1L, "libflexiblas.dll is loaded in the R process")
cat("initial backend:", current(), "\n")

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

set_threads <- function(k) invisible(.C("rfb_set_threads", n = as.integer(k)))
openblas <- function(dll)
    .C("rfb_openblas_info", module = dll, threads = 0L, parallel = 0L,
       config = strrep(" ", 256))
cat(sprintf("cores: %d logical, %d physical; OMP_NUM_THREADS=%s\n",
            parallel::detectCores(), parallel::detectCores(logical = FALSE),
            Sys.getenv("OMP_NUM_THREADS", "(unset)")))
B <- matrix(rnorm(3000^2), 3000)

backends <- c("OPENBLAS-THREADS" = "libopenblas_threads.dll",
              "OPENBLAS-OPENMP"  = "libopenblas_openmp.dll")
for (be in names(backends)) {
    cat("\n==", be, "==\n")
    id <- .C("rfb_load", name = be, id = 0L)$id
    check(id >= 0L, sprintf("load %s (id %d)", be, id))
    check(switch_to(id) == 0L, sprintf("switch to %s", be))
    check(identical(toupper(current()), be), sprintf("current backend reports %s", be))
    info <- openblas(backends[[be]])
    cat(sprintf("config: %s; parallel mode %d (0 serial, 1 threads, 2 OpenMP)\n",
                trimws(info$config), info$parallel))

    res <- work()
    for (k in names(ref)) {
        err <- max(Mod(res[[k]] - ref[[k]])) / max(Mod(ref[[k]]))
        check(err < 1e-10, sprintf("%s agrees with NETLIB (rel err %.1e)", k, abs(err)))
    }

    for (k in unique(c(1L, 2L, max(2L, parallel::detectCores())))) {
        set_threads(k)
        check(threads() == k, sprintf("set %d thread(s): FlexiBLAS reports %d", k, threads()))
        tm <- system.time(B %*% B)
        after <- openblas(backends[[be]])$threads
        check(after == k, sprintf("  OpenBLAS still uses %d after a product (reports %d)", k, after))
        cat(sprintf("  B %%*%% B, n = 3000, %d thread(s): elapsed %.3fs, user %.3fs\n",
                    k, tm[["elapsed"]], tm[["user.self"]]))
    }
}
cat("\n")

check(switch_to(0L) == 0L, "switch back to backend 0")
cat("backend now:", current(), "\n")
cat(sprintf("  B %%*%% B, n = 3000, NETLIB: %.3fs\n", system.time(B %*% B)[["elapsed"]]))
res0 <- work()
check(isTRUE(all.equal(res0$prod, ref$prod)), "results after switching back")

cat("\n")
if (length(failures)) {
    cat("FAILURES:\n", paste0("  ", failures, "\n"), sep = "")
    quit(status = 1)
}
cat("all checks passed\n")

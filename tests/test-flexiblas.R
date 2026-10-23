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

ob <- .C("rfb_load", name = "OPENBLAS", id = 0L)$id
check(ob >= 0L, sprintf("load OPENBLAS backend (id %d)", ob))
check(switch_to(ob) == 0L, "switch to OPENBLAS")
cat("backend now:", current(), "\n")
check(grepl("OPENBLAS", current(), ignore.case = TRUE), "current backend reports OPENBLAS")

res <- work()
for (k in names(ref)) {
    err <- max(Mod(res[[k]] - ref[[k]])) / max(Mod(ref[[k]]))
    check(err < 1e-10, sprintf("%s agrees with NETLIB (rel err %.1e)", k, abs(err)))
}

set_threads <- function(k) invisible(.C("rfb_set_threads", n = as.integer(k)))
B <- matrix(rnorm(2000^2), 2000)
timing <- function() system.time(B %*% B)[["elapsed"]]
for (k in unique(c(1L, 2L, max(2L, parallel::detectCores())))) {
    set_threads(k)
    got <- threads()
    check(got == k, sprintf("set %d thread(s), FlexiBLAS reports %d", k, got))
    cat(sprintf("  B %%*%% B, n = 2000, %d thread(s): %.3fs\n", k, timing()))
}

check(switch_to(0L) == 0L, "switch back to backend 0")
cat("backend now:", current(), "\n")
cat(sprintf("  B %%*%% B, n = 2000, NETLIB: %.3fs\n", timing()))
res0 <- work()
check(isTRUE(all.equal(res0$prod, ref$prod)), "results after switching back")

cat("\n")
if (length(failures)) {
    cat("FAILURES:\n", paste0("  ", failures, "\n"), sep = "")
    quit(status = 1)
}
cat("all checks passed\n")

## Memory of the R process with the OPENBLAS backend. OpenBLAS commits one
## buffer per thread when its thread server starts or the thread count grows,
## so the private (committed) memory is followed through startup, switching
## to OPENBLAS and a range of thread counts. Run with OPENBLAS_NUM_THREADS
## set and unset to see the commit at load.
mem <- function(what) {
    ps <- system2("powershell", c("-NoProfile", "-Command", shQuote(sprintf(
        "$p = Get-Process -Id %d; '{0} {1} {2}' -f $p.PrivateMemorySize64, $p.WorkingSet64, $p.PeakWorkingSet64",
        Sys.getpid()))), stdout = TRUE)
    x <- as.numeric(strsplit(trimws(ps), " ")[[1]]) / 2^20
    cat(sprintf("%-30s private %7.1f MB  working set %7.1f MB  peak %7.1f MB\n",
                what, x[1], x[2], x[3]))
}
cat("OPENBLAS_NUM_THREADS:", Sys.getenv("OPENBLAS_NUM_THREADS", "(unset)"),
    "; cores:", parallel::detectCores(), "\n")
mem("startup")
flexiblas::flexiblas_switch(flexiblas::flexiblas_load_backend("OPENBLAS"))
mem(sprintf("OPENBLAS loaded, %d threads", flexiblas::flexiblas_get_num_threads()))
A <- matrix(rnorm(2000^2), 2000)
mem("2000 x 2000 matrix")
for (k in c(1L, 4L, 16L, 64L, 1L)) {
    flexiblas::flexiblas_set_num_threads(k)
    invisible(A %*% A)
    mem(sprintf("product, %d threads", flexiblas::flexiblas_get_num_threads()))
}

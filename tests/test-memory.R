## Memory of the R process at three points: after startup, after switching to
## the OPENBLAS backend, and after a threaded product. Compares builds, e.g.
## OpenBLAS with different NUM_THREADS.
mem <- function(what) {
    ps <- system2("powershell", c("-NoProfile", "-Command", shQuote(sprintf(
        "$p = Get-Process -Id %d; '{0} {1} {2}' -f $p.PrivateMemorySize64, $p.WorkingSet64, $p.PeakWorkingSet64",
        Sys.getpid()))), stdout = TRUE)
    x <- as.numeric(strsplit(trimws(ps), " ")[[1]]) / 2^20
    cat(sprintf("%-28s private %7.1f MB  working set %7.1f MB  peak %7.1f MB\n",
                what, x[1], x[2], x[3]))
}
mem("startup")
flexiblas::flexiblas_switch(flexiblas::flexiblas_load_backend("OPENBLAS"))
mem("OPENBLAS loaded")
flexiblas::flexiblas_set_num_threads(parallel::detectCores())
A <- matrix(rnorm(2000^2), 2000)
mem("2000 x 2000 matrix")
invisible(A %*% A)
mem(sprintf("product, %d threads", flexiblas::flexiblas_get_num_threads()))

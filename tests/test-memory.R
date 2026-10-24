## Memory of the R process with an OpenBLAS backend (default OPENBLAS, or the
## name given as argument). OpenBLAS sets aside one buffer per thread when its
## thread server starts or the thread count grows, so memory is followed
## through startup, switching backend and a range of thread counts.
## On Windows: private (committed) memory and working set. On Linux: virtual
## size and resident set of the process, and the system's Committed_AS, which
## counts what Windows would commit but is enforced only under strict
## overcommit.
backend <- commandArgs(TRUE)[1]
if (is.na(backend)) backend <- "OPENBLAS"

mem <- if (.Platform$OS.type == "windows") function(what) {
    ps <- system2("powershell", c("-NoProfile", "-Command", shQuote(sprintf(
        "$p = Get-Process -Id %d; '{0} {1}' -f $p.PrivateMemorySize64, $p.WorkingSet64",
        Sys.getpid()))), stdout = TRUE)
    x <- as.numeric(strsplit(trimws(ps), " ")[[1]]) / 2^20
    cat(sprintf("%-30s private %7.0f MB  working set %6.0f MB\n", what, x[1], x[2]))
} else function(what) {
    kb <- function(file, key) {
        l <- grep(paste0("^", key, ":"), readLines(file), value = TRUE)
        as.numeric(gsub("[^0-9]", "", l)) / 1024
    }
    cat(sprintf("%-30s virtual %7.0f MB  resident %6.0f MB  Committed_AS %7.0f MB\n", what,
                kb("/proc/self/status", "VmSize"), kb("/proc/self/status", "VmRSS"),
                kb("/proc/meminfo", "Committed_AS")))
}

cat("backend:", backend, "; OPENBLAS_NUM_THREADS:", Sys.getenv("OPENBLAS_NUM_THREADS", "(unset)"),
    "; cores:", parallel::detectCores(), "\n")
mem("startup")
flexiblas::flexiblas_switch(flexiblas::flexiblas_load_backend(backend))
mem(sprintf("%s loaded, %d threads", backend, flexiblas::flexiblas_get_num_threads()))
A <- matrix(rnorm(2000^2), 2000)
mem("2000 x 2000 matrix")
for (k in c(1L, 4L, 16L, 64L, 1L)) {
    flexiblas::flexiblas_set_num_threads(k)
    invisible(A %*% A)
    mem(sprintf("product, %d threads", flexiblas::flexiblas_get_num_threads()))
}

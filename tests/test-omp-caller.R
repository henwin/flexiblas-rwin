## BLAS called from several threads at once: an OpenMP loop over dgemm in
## compiled code (omp-caller.c, built here with R CMD SHLIB and the R
## OpenMP flags, so on Windows with its own static libgomp like a package),
## against each FlexiBLAS backend with the default BLAS thread count and
## with one. Records the time and how many threads the process has
## afterwards, since the libgomp pools and the OpenBLAS workers stay.
##   Rscript test-omp-caller.R [n] [reps]
args <- commandArgs(TRUE)
n <- if (length(args)) as.integer(args[1]) else 1000L
reps <- if (length(args) > 1) as.integer(args[2]) else 2L

src <- file.path(dirname(sub("--file=", "", grep("--file=", commandArgs(), value = TRUE))), "omp-caller.c")
dir <- tempfile("omp-caller"); dir.create(dir); invisible(file.copy(src, dir))
writeLines(c("PKG_CFLAGS = $(SHLIB_OPENMP_CFLAGS)", "PKG_LIBS = $(SHLIB_OPENMP_CFLAGS) $(BLAS_LIBS)"),
           file.path(dir, "Makevars"))
owd <- setwd(dir)
status <- system2(file.path(R.home("bin"), "R"), c("CMD", "SHLIB", "omp-caller.c"), stdout = "shlib.log", stderr = "shlib.log")
setwd(owd)
if (status != 0) { cat(readLines(file.path(dir, "shlib.log")), sep = "\n"); stop("R CMD SHLIB failed") }
dyn.load(file.path(dir, paste0("omp-caller", .Platform$dynlib.ext)))

threads <- function() {
    if (.Platform$OS.type == "windows")
        as.integer(system2("powershell", c("-NoProfile", "-Command",
                   sprintf("(Get-Process -Id %d).Threads.Count", Sys.getpid())), stdout = TRUE))
    else if (file.exists("/proc/self/task")) length(list.files("/proc/self/task"))
    else NA_integer_
}
cores <- parallel::detectCores()
fb <- requireNamespace("flexiblas", quietly = TRUE) && flexiblas::flexiblas_avail()
backends <- if (fb) setdiff(flexiblas::flexiblas_list(), "__FALLBACK__") else "current BLAS"

cat(R.version.string, "on", R.version$platform, "\n")
cat("cores:", cores, " n:", n, " dgemm calls per OpenMP thread:", reps, "\n")
cat("threads at start:", threads(), "\n\n")
cat(sprintf("%-18s %-14s %-12s %10s %8s\n", "backend", "OpenMP threads", "BLAS threads", "time (s)", "threads"))
for (be in backends) {
    if (fb) flexiblas::flexiblas_switch(flexiblas::flexiblas_load_backend(be))
    t0 <- if (fb) flexiblas::flexiblas_get_num_threads() else NA
    for (m in unique(c(1L, cores))) for (bt in if (fb) unique(c(t0, 1L)) else NA) {
        if (fb) flexiblas::flexiblas_set_num_threads(bt)
        el <- system.time(.Call("omp_caller", n, m, reps))[["elapsed"]]
        cat(sprintf("%-18s %-14d %-12s %10.2f %8d\n", be, m,
                    if (is.na(bt)) "" else as.character(bt), el, threads()))
    }
    if (fb) flexiblas::flexiblas_set_num_threads(t0)
}

## A BLAS and a LAPACK routine called with an invalid argument, from
## compiled code built here with R CMD SHLIB (xerbla.c) and linked as a
## package is, under every FlexiBLAS backend: each must end in R's error
## "BLAS/LAPACK routine 'DGEMM ' gave error code -1", which R's xerbla
## signals, not in a process exit or a message R never sees.
##   Rscript test-xerbla.R
src <- file.path(dirname(sub("--file=", "", grep("--file=", commandArgs(), value = TRUE))), "xerbla.c")
dir <- tempfile("xerbla"); dir.create(dir); invisible(file.copy(src, dir))
writeLines("PKG_LIBS = $(LAPACK_LIBS) $(BLAS_LIBS) $(FLIBS)", file.path(dir, "Makevars"))
owd <- setwd(dir)
status <- system2(file.path(R.home("bin"), "R"), c("CMD", "SHLIB", "xerbla.c"), stdout = "shlib.log", stderr = "shlib.log")
setwd(owd)
cat(readLines(file.path(dir, "shlib.log")), sep = "\n")
if (status != 0) stop("R CMD SHLIB failed")
dyn.load(file.path(dir, paste0("xerbla", .Platform$dynlib.ext)))

fb <- requireNamespace("flexiblas", quietly = TRUE) && flexiblas::flexiblas_avail()
backends <- if (fb) flexiblas::flexiblas_list() else "R's own"
failures <- 0L
for (be in backends) {
    if (fb) flexiblas::flexiblas_switch(flexiblas::flexiblas_load_backend(be))
    for (f in c(DGEMM = "bad_dgemm", DPOTRF = "bad_dpotrf")) {
        msg <- tryCatch({ .Call(f); "no error" }, error = conditionMessage)
        ## the name as xerbla got it, padded or not
        ok <- grepl(sprintf("routine '%s *' gave error code -1", names(f)), msg)
        cat(sprintf("%-18s %-7s %s: %s\n", be, names(f), if (ok) "ok" else "FAILED", msg))
        failures <- failures + !ok
    }
}
cat(failures, "failures\n")
quit(status = as.integer(failures > 0))

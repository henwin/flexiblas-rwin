## A BLAS and a LAPACK routine called with an invalid argument, from
## compiled code built here with R CMD SHLIB (xerbla.c) and linked as a
## package is, under every FlexiBLAS backend: each must end in R's error
## "BLAS/LAPACK routine 'DGEMM ' gave error code -1", which R's xerbla
## signals, not in a process exit or a message R never sees.  Writes the
## file xerbla.ok last, and only without failures: a xerbla that ends the
## process (reference xerbla.f stops with status 0) leaves no file.
##   Rscript test-xerbla.R
invisible(Sys.setLanguage("en"))
unlink("xerbla.ok")
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
    for (r in c("DGEMM", "DPOTRF")) {
        msg <- tryCatch({ .Call(paste0("bad_", tolower(r))); "no error" }, error = conditionMessage)
        ## the name as xerbla got it, padded on either side or followed by
        ## what R's xerbla reads past an unterminated Fortran name
        ok <- grepl(sprintf("routine ' *%s[^']*' gave error code -1$", r), msg)
        cat(sprintf("%-18s %-7s %s: %s\n", be, r, if (ok) "ok" else "FAILED", msg))
        failures <- failures + !ok
    }
}
cat(failures, "failures\n")
if (failures == 0L) writeLines("ok", "xerbla.ok")
quit(status = as.integer(failures > 0))

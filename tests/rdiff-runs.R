## tools::Rdiff of every output of R CMD check in the first run against
## the same output of each other run, printed in full:
##   Rscript rdiff-runs.R RUN1 RUN2... -- PACKAGE...
## A run is a directory with PACKAGE.Rcheck in it and the output of
## R CMD check beside it as PACKAGE.out.  The outputs are PACKAGE.out,
## which holds 00check.log and what went to stderr, 00install.out and
## every *.Rout and *.Rout.fail; one missing in a run is said so.  Rdiff
## compares as R CMD check compares with .Rout.save, with forEx for the
## examples.  Under MAKEFLAGS=-j the compiler output in 00install.out can
## come in another order from run to run.
a <- commandArgs(TRUE)
runs <- a[seq_len(match("--", a) - 1L)]
pkgs <- a[-seq_len(match("--", a))]
for (p in pkgs) {
    files <- function(r) {
        d <- file.path(r, paste0(p, ".Rcheck"))
        f <- list.files(d, "^00install\\.out$|\\.Rout(\\.fail)?$", recursive = TRUE)
        c(if (file.exists(file.path(r, paste0(p, ".out")))) paste0(p, ".out"),
          f[!grepl("^00_pkg_src/", f)])
    }
    ## an output that failed in a run is its .Rout.fail there
    path <- function(r, f) {
        x <- if (f == paste0(p, ".out")) file.path(r, f)
             else file.path(r, paste0(p, ".Rcheck"), c(f, paste0(f, ".fail")))
        x[file.exists(x)][1]
    }
    all <- sort(unique(sub("\\.fail$", "", unlist(lapply(runs, files)))))
    for (f in all) for (r in runs[-1]) {
        x <- path(runs[1], f); y <- path(r, f)
        rel <- function(z)
            if (is.na(z)) f else if (grepl("\\.Rcheck/", z)) sub(".*\\.Rcheck/", "", z) else basename(z)
        cat(sprintf("== %s %s: %s against %s\n", p, f, file.path(runs[1], rel(x)), file.path(r, rel(y))))
        if (is.na(x) || is.na(y)) {
            cat("missing in", paste(c(runs[1], r)[is.na(c(x, y))], collapse = " and "), "\n")
            next
        }
        out <- tools::Rdiff(x, y, useDiff = TRUE, forEx = grepl("-Ex\\.Rout$", f), Log = TRUE)$out
        writeLines(if (length(out)) out else "no differences")
    }
}

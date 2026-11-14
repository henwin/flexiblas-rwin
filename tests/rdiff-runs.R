## tools::Rdiff of every output of R CMD check in the first run against
## the same output of each other run, printed in full:
##   Rscript rdiff-runs.R RUN1 RUN2... -- PACKAGE...
## A run is a directory with PACKAGE.Rcheck in it.  The outputs are
## 00check.log and every *.Rout and *.Rout.fail; one missing in a run is
## said so.  Rdiff compares as R CMD check compares with .Rout.save, with
## forEx for the examples.
a <- commandArgs(TRUE)
runs <- a[seq_len(match("--", a) - 1L)]
pkgs <- a[-seq_len(match("--", a))]
for (p in pkgs) {
    files <- function(r) {
        d <- file.path(r, paste0(p, ".Rcheck"))
        f <- list.files(d, "^00check\\.log$|\\.Rout(\\.fail)?$", recursive = TRUE)
        f[!grepl("^00_pkg_src/", f)]
    }
    ## an output that failed in a run is its .Rout.fail there
    path <- function(r, f) {
        x <- file.path(r, paste0(p, ".Rcheck"), c(f, paste0(f, ".fail")))
        x[file.exists(x)][1]
    }
    all <- sort(unique(sub("\\.fail$", "", unlist(lapply(runs, files)))))
    for (f in all) for (r in runs[-1]) {
        x <- path(runs[1], f); y <- path(r, f)
        rel <- function(z) if (is.na(z)) f else sub(".*\\.Rcheck/", "", z)
        cat(sprintf("== %s %s: %s against %s\n", p, f, file.path(runs[1], rel(x)), file.path(r, rel(y))))
        if (is.na(x) || is.na(y)) {
            cat("missing in", paste(c(runs[1], r)[is.na(c(x, y))], collapse = " and "), "\n")
            next
        }
        out <- tools::Rdiff(x, y, useDiff = TRUE, forEx = grepl("-Ex\\.Rout$", f), Log = TRUE)$out
        writeLines(if (length(out)) out else "no differences")
    }
}

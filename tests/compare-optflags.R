## Build CRAN packages from source with R's package flags (-O2) and with -O3,
## as R would without the sed in src/gnuwin32/fixed/Makefile (r57974), run
## their examples and tests, and compare the outputs of the two builds.
##   Rscript compare-optflags.R mvtnorm [more packages]
pkgs <- commandArgs(TRUE)
if (!length(pkgs)) pkgs <- "mvtnorm"
repos <- "https://cloud.r-project.org"
work <- normalizePath(file.path(tempdir(), "optflags"), mustWork = FALSE)
dir.create(work, showWarnings = FALSE)

## Dependencies, Suggests included, as binaries; the packages themselves
## from source, once per flag set.
install.packages(pkgs, repos = repos, dependencies = TRUE, quiet = TRUE)
src <- download.packages(pkgs, destdir = work, repos = repos, type = "source", quiet = TRUE)

eopts <- "-mfpmath=sse -msse2 -mstackrealign"
mk <- c(O2 = "", O3 = file.path(work, "Makevars-O3"))
writeLines(c(sprintf("CFLAGS = -O3 -Wall -std=gnu2x %s", eopts),
             sprintf("FFLAGS = -O3 %s", eopts),
             sprintf("FCFLAGS = -O3 %s", eopts)), mk[["O3"]])

for (opt in names(mk)) {
    lib <- file.path(work, paste0("lib-", opt))
    dir.create(lib, showWarnings = FALSE)
    Sys.setenv(R_MAKEVARS_USER = mk[[opt]])
    for (i in seq_len(nrow(src))) {
        log <- file.path(work, sprintf("install-%s-%s.log", src[i, 1], opt))
        system2(file.path(R.home("bin"), "R"),
                c("CMD", "INSTALL", "--preclean", "--install-tests", paste0("--library=", shQuote(lib)), shQuote(src[i, 2])),
                stdout = log, stderr = log)
        cc <- grep("^(gcc|gfortran|g\\+\\+) .* -c ", readLines(log), value = TRUE)
        cat(sprintf("%-12s %s: %d compiles, flags %s\n", src[i, 1], opt, length(cc),
                    paste(unique(regmatches(cc, regexpr("-O[0-3s]", cc))), collapse = " ")))
    }
}
Sys.unsetenv("R_MAKEVARS_USER")

## testInstalledPackage() runs each file in R --vanilla, which skips the
## profiles; R_DEFAULT_PACKAGES is still read, so a package attached there
## seeds the RNG in every run and makes tests that draw random numbers
## reproducible.
seed <- file.path(work, "seedone")
dir.create(file.path(seed, "R"), recursive = TRUE, showWarnings = FALSE)
writeLines(c("Package: seedone", "Version: 1.0", "Title: Seed the RNG",
             "Description: Calls set.seed(1) when loaded.", "License: GPL-2",
             "Author: none", "Maintainer: none <none@example.org>"),
           file.path(seed, "DESCRIPTION"))
writeLines(".onLoad <- function(libname, pkgname) set.seed(1)",
           file.path(seed, "R", "zzz.R"))
system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL", paste0("--library=", shQuote(.Library)), shQuote(seed)))
Sys.setenv(R_DEFAULT_PACKAGES = "datasets,utils,grDevices,graphics,stats,methods,seedone")

## Examples and tests of each build; testInstalledPackage() writes .Rout files.
## The -O2 build runs twice ("O2b"), so that differences from run to run can
## be told from differences between the builds.
for (opt in c(names(mk), "O2b")) for (p in pkgs) {
    lib <- file.path(work, paste0("lib-", sub("b$", "", opt)))
    out <- file.path(work, paste0("out-", opt), p)
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    old <- .libPaths(); .libPaths(c(lib, old))
    try(tools::testInstalledPackage(p, lib.loc = lib, outDir = out,
                                    types = c("examples", "tests")))
    .libPaths(old)
}

## Compare the outputs, ignoring lines with timings.
compare <- function(x, y) {
ndiff <- 0L
for (p in pkgs) {
    a <- file.path(work, paste0("out-", x), p); b <- file.path(work, paste0("out-", y), p)
    files <- sort(union(list.files(a, "\\.Rout$", recursive = TRUE),
                        list.files(b, "\\.Rout$", recursive = TRUE)))
    cat(sprintf("\n== %s, %s against %s: %d output files\n", p, y, x, length(files)))
    for (f in files) {
        la <- if (file.exists(file.path(a, f))) readLines(file.path(a, f)) else "(missing)"
        lb <- if (file.exists(file.path(b, f))) readLines(file.path(b, f)) else "(missing)"
        ## drop timings: system.time()'s header and the line of values under it
        keep <- function(l) {
            h <- grep("user +system +elapsed", l)
            if (length(h)) l <- l[-c(h, h + 1L)]
            l[!grepl("Time|elapsed|seconds", l)]
        }
        la <- keep(la); lb <- keep(lb)
        if (identical(la, lb)) {
            cat(sprintf("%-40s identical\n", f))
        } else {
            ndiff <- ndiff + 1L
            n <- max(length(la), length(lb))
            d <- which(rep_len(la, n) != rep_len(lb, n))
            cat(sprintf("%-40s %d lines differ\n", f, length(d)))
            for (k in head(d, 6)) cat(sprintf("  %s: %s\n  %s: %s\n", x, la[k], y, lb[k]))
        }
    }
}
cat("\n", ndiff, "output files differ between", x, "and", y, "\n")
}
compare("O2", "O2b")
compare("O2", "O3")

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
## every compiler R's Makeconf sets flags for, C++ standards included
writeLines(c(sprintf("CFLAGS = -O3 -Wall -std=gnu2x %s", eopts),
             sprintf("%s = -O3 -Wall %s", c("CXXFLAGS", paste0("CXX", c(11, 14, 17, 20, 23, 26), "FLAGS")), eopts),
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
writeLines("", file.path(seed, "NAMESPACE"))
seedlib <- file.path(work, "seedlib")
dir.create(seedlib, showWarnings = FALSE)
system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL", paste0("--library=", shQuote(seedlib)), shQuote(seed)))
stopifnot(file.exists(file.path(seedlib, "seedone", "DESCRIPTION")))
Sys.setenv(R_LIBS_SITE = seedlib,
           R_DEFAULT_PACKAGES = "datasets,utils,grDevices,graphics,stats,methods,seedone")

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

## Compare the outputs. Lines that differ between the two runs of the -O2
## build (addresses, dates, timings, packages' own random numbers) say
## nothing about the flags; only lines that agree between O2 and O2b and
## differ in O3 do. Addresses are blanked before comparing.
norm <- function(f) {
    if (!file.exists(f)) return(NULL)
    l <- readLines(f, warn = FALSE)
    h <- grep("user +system +elapsed", l)
    if (length(h)) l <- l[-c(h, h + 1L)]
    gsub('0x[0-9a-fA-F]+|<[0-9A-F]{8,16}>|"[0-9a-f]{16}"', "ADDR", l)
}
nflag <- 0L
for (p in pkgs) {
    dir <- function(x) file.path(work, paste0("out-", x), p)
    files <- sort(unique(unlist(lapply(c("O2", "O2b", "O3"), function(x)
        list.files(dir(x), "\\.Rout$", recursive = TRUE)))))
    noisy <- 0L; flagged <- character()
    for (f in files) {
        a <- norm(file.path(dir("O2"), f)); b <- norm(file.path(dir("O2b"), f)); c <- norm(file.path(dir("O3"), f))
        if (is.null(a) || is.null(b) || is.null(c)) { flagged <- c(flagged, f); cat(sprintf("  %s: missing in a build\n", f)); next }
        if (length(a) != length(b)) { noisy <- noisy + 1L; next }
        if (!identical(a, b)) noisy <- noisy + 1L
        if (length(c) != length(a)) {
            flagged <- c(flagged, f)
            cat(sprintf("  %s: %d lines with -O2, %d with -O3\n", f, length(a), length(c)))
            next
        }
        d <- which(a == b & a != c)
        if (length(d)) {
            flagged <- c(flagged, f)
            cat(sprintf("  %s: %d stable lines differ with -O3\n", f, length(d)))
            for (k in head(d, 3)) cat(sprintf("    O2: %s\n    O3: %s\n", substr(a[k], 1, 100), substr(c[k], 1, 100)))
        }
    }
    nflag <- nflag + length(flagged)
    cat(sprintf("== %-12s %3d output files, %3d vary between runs, %3d differ with -O3\n", p, length(files), noisy, length(flagged)))
}
cat(sprintf("== %d output files differ with -O3\n", nflag))

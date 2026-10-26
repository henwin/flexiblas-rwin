## Compare the outputs of examples and tests between builds: CRAN packages
## built with R's package flags (-O2) and with -O3, as R would build them
## without the sed in src/gnuwin32/fixed/Makefile (r57974), or R's own and
## packages' tests with R's Rblas.dll and with one built with -O3.
##   Rscript compare-optflags.R build O2|O3 PKG...    install PKG from source into lib-O2 or lib-O3
##   Rscript compare-optflags.R binary PKG...         install CRAN's binary of PKG and add the tests from its source
##   Rscript compare-optflags.R test RUN LIB PKG...   examples and tests of PKG in lib-LIB (LIB "default": the first library), into out-RUN
##   Rscript compare-optflags.R base RUN              R's tests (testInstalledBasic, recommended packages), into out-RUN
##   Rscript compare-optflags.R compare A A2 B        out-B against out-A, on the lines out-A and out-A2 agree on
## The R running "test" and "base" is the one whose output is recorded; the
## directories are in $OPTFLAGS_WORK, or optflags-work.
args <- commandArgs(TRUE)
mode <- args[1]
## with / on Windows: testInstalledPackage() pastes the library path into R
## code, where a backslash starts an escape
work <- normalizePath(Sys.getenv("OPTFLAGS_WORK", "optflags-work"), winslash = "/", mustWork = FALSE)
dir.create(work, showWarnings = FALSE)
repos <- "https://cloud.r-project.org"

if (mode == "build") {
    opt <- args[2]; pkgs <- args[-(1:2)]
    ## dependencies, Suggests included, as binaries, once
    if (opt == "O2") install.packages(pkgs, repos = repos, dependencies = TRUE, quiet = TRUE)
    src <- download.packages(pkgs, destdir = work, repos = repos, type = "source", quiet = TRUE)
    mk <- ""
    if (opt == "O3") {
        eopts <- "-mfpmath=sse -msse2 -mstackrealign"
        mk <- file.path(work, "Makevars-O3")
        ## every compiler R's Makeconf sets flags for, C++ standards included
        writeLines(c(sprintf("CFLAGS = -O3 -Wall -std=gnu2x %s", eopts),
                     sprintf("%s = -O3 -Wall %s", c("CXXFLAGS", paste0("CXX", c(11, 14, 17, 20, 23, 26), "FLAGS")), eopts),
                     sprintf("FFLAGS = -O3 %s", eopts),
                     sprintf("FCFLAGS = -O3 %s", eopts)), mk)
    }
    lib <- file.path(work, paste0("lib-", opt))
    dir.create(lib, showWarnings = FALSE)
    Sys.setenv(R_MAKEVARS_USER = mk)
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

if (mode == "binary") {
    ## CRAN's binaries, built with R's package flags, with their
    ## dependencies, Suggests included; binaries leave out the tests, so
    ## they are copied from the source package
    pkgs <- args[-1]
    install.packages(pkgs, repos = repos, dependencies = TRUE, type = "binary", quiet = TRUE)
    src <- download.packages(pkgs, destdir = work, repos = repos, type = "source", quiet = TRUE)
    for (i in seq_len(nrow(src))) {
        p <- src[i, 1]
        inst <- tryCatch(find.package(p), error = function(e) "")
        if (!nzchar(inst)) { cat(sprintf("%-12s not installed\n", p)); next }
        files <- untar(src[i, 2], list = TRUE)
        t <- grep(sprintf("^%s/tests/", p), files, value = TRUE)
        if (length(t)) {
            untar(src[i, 2], files = t, exdir = work)
            file.copy(file.path(work, p, "tests"), inst, recursive = TRUE)
        }
        cat(sprintf("%-12s binary %s, %d test files\n", p, packageVersion(p), length(t)))
    }
}

if (mode == "test") {
    run <- args[2]
    lib <- if (args[3] == "default") .libPaths()[1] else file.path(work, paste0("lib-", args[3]))
    pkgs <- args[-(1:3)]
    ## testInstalledPackage() runs each file in R --vanilla, which skips the
    ## profiles; R_DEFAULT_PACKAGES is still read, so a package attached
    ## there seeds the RNG in every run and makes tests that draw random
    ## numbers with R's generator reproducible.
    seedlib <- file.path(work, "seedlib")
    if (!file.exists(file.path(seedlib, "seedone", "DESCRIPTION"))) {
        seed <- file.path(work, "seedone")
        dir.create(file.path(seed, "R"), recursive = TRUE, showWarnings = FALSE)
        writeLines(c("Package: seedone", "Version: 1.0", "Title: Seed the RNG",
                     "Description: Calls set.seed(1) when loaded.", "License: GPL-2",
                     "Author: none", "Maintainer: none <none@example.org>"),
                   file.path(seed, "DESCRIPTION"))
        writeLines(".onLoad <- function(libname, pkgname) set.seed(1)", file.path(seed, "R", "zzz.R"))
        writeLines("", file.path(seed, "NAMESPACE"))
        dir.create(seedlib, showWarnings = FALSE)
        system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL", paste0("--library=", shQuote(seedlib)), shQuote(seed)))
        stopifnot(file.exists(file.path(seedlib, "seedone", "DESCRIPTION")))
    }
    Sys.setenv(R_LIBS_SITE = seedlib,
               R_DEFAULT_PACKAGES = "datasets,utils,grDevices,graphics,stats,methods,seedone")
    cat(sprintf("%s: %s\n", run, R.home()))
    .libPaths(c(lib, .libPaths()))
    for (p in pkgs) {
        out <- file.path(work, paste0("out-", run), p)
        dir.create(out, recursive = TRUE, showWarnings = FALSE)
        try(tools::testInstalledPackage(p, lib.loc = lib, outDir = out, types = c("examples", "tests")))
    }
}

if (mode == "base") {
    run <- args[2]
    cat(sprintf("%s: %s; tests %s\n", run, R.home(),
                if (dir.exists(file.path(R.home(), "tests"))) "installed" else "NOT installed"))
    out <- file.path(work, paste0("out-", run))
    dir.create(file.path(out, "base"), recursive = TRUE, showWarnings = FALSE)
    dir.create(file.path(out, "recommended"), showWarnings = FALSE)
    ## failures are part of the result, not reasons to stop
    for (s in c("basic", "devel"))
        cat(sprintf("testInstalledBasic(\"%s\"): %s\n", s,
                    tryCatch(tools::testInstalledBasic(s, outDir = file.path(out, "base")),
                             error = function(e) conditionMessage(e))))
    cat(sprintf("testInstalledPackages: %s\n",
                tryCatch(tools::testInstalledPackages(outDir = file.path(out, "recommended"), scope = "recommended",
                                                      types = c("examples", "tests"), errorsAreFatal = FALSE),
                         error = function(e) conditionMessage(e))))
}

if (mode == "compare") {
    ## Lines that differ between runs A and A2 (addresses, dates, timings,
    ## packages' own random numbers) say nothing about what B changes; a line
    ## counts only when A and A2 agree on it and B does not. Addresses and
    ## system.time() values are blanked first.
    run <- args[2:4]
    norm <- function(f) {
        if (!file.exists(f)) return(NULL)
        l <- readLines(f, warn = FALSE, encoding = "bytes")
        h <- grep("user +system +elapsed", l)
        if (length(h)) l <- l[-c(h, h + 1L)]
        ## byte-wise: outputs need not be valid in the session's encoding
        l <- gsub('0x[0-9a-fA-F]+|<[0-9A-F]{8,16}>|"[0-9a-f]{16}"', "ADDR", l, useBytes = TRUE)
        l <- gsub("C:/R-o3", "C:/R", l, fixed = TRUE, useBytes = TRUE)   # the copy with the -O3 BLAS
        ## widths of columns follow their widest entry, a path or a timing
        gsub(" +", " ", trimws(l, "right"), useBytes = TRUE)
    }
    ## c(noisy, flagged) for one output file
    one <- function(g, f) {
        dir <- function(r) file.path(work, paste0("out-", r), g)
        a <- norm(file.path(dir(run[1]), f)); a2 <- norm(file.path(dir(run[2]), f)); b <- norm(file.path(dir(run[3]), f))
        if (is.null(a) || is.null(a2) || is.null(b)) {
            cat(sprintf("  %s: missing in %s\n", f, paste(run[c(is.null(a), is.null(a2), is.null(b))], collapse = ", ")))
            return(c(0L, 1L))
        }
        noisy <- as.integer(!identical(a, a2))
        if (length(a) != length(a2)) return(c(noisy, 0L))
        if (length(b) != length(a)) {
            cat(sprintf("  %s: %d lines in %s, %d in %s\n", f, length(a), run[1], length(b), run[3]))
            return(c(noisy, 1L))
        }
        d <- which(a == a2 & a != b)
        if (length(d)) {
            cat(sprintf("  %s: %d stable lines differ\n", f, length(d)))
            for (k in head(d, 3))
                cat(sprintf("    %s: %s\n    %s: %s\n", run[1], substr(a[k], 1, 100), run[3], substr(b[k], 1, 100)))
        }
        c(noisy, as.integer(length(d) > 0))
    }
    groups <- list.dirs(file.path(work, paste0("out-", run[1])), full.names = FALSE, recursive = FALSE)
    nflag <- 0L
    for (g in groups) {
        files <- sort(unique(unlist(lapply(run, function(r)
            list.files(file.path(work, paste0("out-", r), g), "\\.Rout$", recursive = TRUE)))))
        n <- c(0L, 0L)
        for (f in files)
            n <- n + tryCatch(one(g, f), error = function(e) {
                cat(sprintf("  %s: not compared: %s\n", f, conditionMessage(e))); c(0L, 1L) })
        nflag <- nflag + n[2]
        cat(sprintf("== %-12s %3d output files, %3d vary between %s and %s, %3d differ in %s\n",
                    g, length(files), n[1], run[1], run[2], n[2], run[3]))
    }
    cat(sprintf("== %d output files differ in %s\n", nflag, run[3]))
}

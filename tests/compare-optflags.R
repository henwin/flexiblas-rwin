## Run the examples and tests of packages for a comparison between builds: CRAN packages
## built with R's package flags (-O2) and with -O3, as R would build them
## without the sed in src/gnuwin32/fixed/Makefile (r57974), or packages'
## examples and tests with R's Rblas.dll and with one built with -O3.
##   Rscript compare-optflags.R build O2|O3 PKG...    install PKG from source into lib-O2 or lib-O3
##   Rscript compare-optflags.R binary PKG...         install CRAN's binary of PKG and add the tests from its source;
##                                                   appends PKG and installed, not installed or version mismatch
##                                                   to binary.tsv
##   Rscript compare-optflags.R test RUN LIB PKG...   examples and tests of PKG in lib-LIB (LIB "default": the first library), into out-RUN
##   Rscript compare-optflags.R base RUN              examples and tests of the recommended packages, into
##                                                   out-RUN/recommended; fails if one has no example output
## The R running "test" and "base" is the one whose output is recorded; the
## directories are in $OPTFLAGS_WORK, or optflags-work. compare-runs.R
## compares the runs.
## o3-packages.yml runs the Rblas.dll comparison. The package-flags comparison
## (r57974) was run on 32 packages with
##   build O2 PKG...; build O3 PKG...; test O2 O2 PKG...; test O2b O2 PKG...;
##   test O3 O3 PKG...; and compare-runs.R work/out-O2/%s,work/out-O2b/%s work/out-O3/%s PKG...
## and found only paths, timings and build dates differing.
args <- commandArgs(TRUE)
mode <- args[1]
## with / on Windows: testInstalledPackage() pastes the library path into R
## code, where a backslash starts an escape
work <- normalizePath(Sys.getenv("OPTFLAGS_WORK", "optflags-work"), winslash = "/", mustWork = FALSE)
dir.create(work, showWarnings = FALSE)
## CRAN and the Bioconductor release that goes with this R (R's own
## repositories file), for packages whose Suggests come from there
setRepositories(ind = 1:4)
repos <- getOption("repos")
repos["CRAN"] <- "https://cloud.r-project.org"

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
        if (!nzchar(inst)) {
            cat(sprintf("%-12s not installed\n", p))
            cat(p, "not installed\n", sep = "\t", file = "binary.tsv", append = TRUE)
            next
        }
        files <- untar(src[i, 2], list = TRUE)
        t <- grep(sprintf("^%s/tests/", p), files, value = TRUE)
        if (length(t)) {
            untar(src[i, 2], files = t, exdir = work)
            file.copy(file.path(work, p, "tests"), inst, recursive = TRUE)
        }
        ## the tests must be those of the version the binary was built from
        srcver <- sub(sprintf("^%s_(.*)\\.tar\\.gz$", p), "\\1", basename(src[i, 2]))
        cat(sprintf("%-12s binary %s, %d test files%s\n", p, packageVersion(p), length(t),
                    if (packageVersion(p) == srcver) "" else sprintf(", from source %s: VERSION MISMATCH", srcver)))
        cat(p, if (packageVersion(p) == srcver) "installed\n" else "version mismatch\n",
            sep = "\t", file = "binary.tsv", append = TRUE)
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
    ## testInstalledPackage() clears R_LIBS for the files it runs, and their
    ## library(pkg) names no library; R_LIBS_USER, searched before the site
    ## library, is what puts lib first for them, and R_LIBS the same for
    ## anything else, over a value from the environment. .libPaths() here
    ## only serves find.package() below.
    .libPaths(c(lib, .libPaths()))
    libs <- paste(setdiff(.libPaths(), .Library), collapse = .Platform$path.sep)
    Sys.setenv(R_LIBS = libs, R_LIBS_USER = libs,
               R_LIBS_SITE = seedlib,
               R_DEFAULT_PACKAGES = "datasets,utils,grDevices,graphics,stats,methods,seedone")
    cat(sprintf("%s: %s\n", run, R.home()))
    for (p in pkgs) {
        out <- file.path(work, paste0("out-", run), p)
        dir.create(out, recursive = TRUE, showWarnings = FALSE)
        ## the library a fresh R loads p from, as the test files will
        from <- system2(file.path(R.home("bin"), "Rscript"), c("--vanilla", "-e",
                        shQuote(sprintf("cat(dirname(find.package('%s')))", p))), stdout = TRUE)
        cat(sprintf("%s %s: loads from %s\n", p, run, paste(from, collapse = " ")))
        if (normalizePath(from, winslash = "/") != normalizePath(lib, winslash = "/"))
            stop(p, " would load from ", from, ", not ", lib)
        ## 1L when an example or test file failed; its output is then a
        ## .Rout.fail, which "compare" reports
        st <- try(tools::testInstalledPackage(p, lib.loc = lib, outDir = out, types = c("examples", "tests")))
        if (!identical(st, 0L)) cat(sprintf("%s %s: tests failed\n", p, run))
    }
}

if (mode == "base") {
    ## R's own tests cannot run here: CRAN's binary installs only part of
    ## tests/, and testInstalledBasic() finds none of its files (R built
    ## with the -O3 Rblas.dll runs them, build-r.yml). A package whose
    ## examples fail does not run its tests (testInstalledPackage()), so
    ## only the example output is required.
    run <- args[2]
    cat(sprintf("%s: %s\n", run, R.home()))
    out <- file.path(work, paste0("out-", run), "recommended")
    dir.create(out, recursive = TRUE, showWarnings = FALSE)
    ## failures are part of the result, not reasons to stop
    cat(sprintf("testInstalledPackages: %s\n",
                tryCatch(tools::testInstalledPackages(outDir = out, scope = "recommended",
                                                      types = c("examples", "tests"), errorsAreFatal = FALSE),
                         error = function(e) conditionMessage(e))))
    ## the packages testInstalledPackages() takes, whether installed or not
    rec <- tools:::.get_standard_package_names()$recommended
    none <- rec[!file.exists(file.path(out, paste0(rec, "-Ex.Rout"))) &
                !file.exists(file.path(out, paste0(rec, "-Ex.Rout.fail")))]
    if (!length(rec) || length(none))
        stop("no output of the examples of ", if (length(rec)) paste(none, collapse = ", ") else "any package")
}

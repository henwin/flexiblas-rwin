## Compare the outputs of examples and tests between builds: CRAN packages
## built with R's package flags (-O2) and with -O3, as R would build them
## without the sed in src/gnuwin32/fixed/Makefile (r57974), or R's own and
## packages' tests with R's Rblas.dll and with one built with -O3.
##   Rscript compare-optflags.R build O2|O3 PKG...    install PKG from source into lib-O2 or lib-O3
##   Rscript compare-optflags.R binary PKG...         install CRAN's binary of PKG and add the tests from its source
##   Rscript compare-optflags.R test RUN LIB PKG...   examples and tests of PKG in lib-LIB (LIB "default": the first library), into out-RUN
##   Rscript compare-optflags.R base RUN              R's tests (testInstalledBasic, recommended packages), into out-RUN
##   Rscript compare-optflags.R compare A,A2.. B,B2.. [PKG...]  the B runs against the A runs, on the lines each
##                                                   set agrees on ("compare A A2 B" is "compare A,A2 B")
## The R running "test" and "base" is the one whose output is recorded; the
## directories are in $OPTFLAGS_WORK, or optflags-work.
## cran-blas.yml runs the Rblas.dll comparison. The package-flags comparison
## (r57974) was run on 32 packages with
##   build O2 PKG...; build O3 PKG...; test O2 O2 PKG...; test O2b O2 PKG...;
##   test O3 O3 PKG...; compare O2 O2b O3
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
        if (!nzchar(inst)) { cat(sprintf("%-12s not installed\n", p)); next }
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
    ## Lines that differ between runs of the reference (addresses, dates,
    ## timings, packages' own random numbers) say nothing about what the
    ## alternative changes; a line counts only when every run of the
    ## reference agrees on it, every run of the alternative agrees on it, and
    ## the two disagree. Addresses, system.time() values and the test
    ## frameworks' own timings are blanked first.
    ## "compare A A2 B" is "compare A,A2 B". The packages are those with
    ## output from the first run of the reference unless given; a run that
    ## lacks a package's output is reported as missing.
    a <- args[-1]
    if (length(a) == 3 && !grepl(",", a[1])) a <- c(paste(a[1:2], collapse = ","), a[3])
    ref <- strsplit(a[1], ",")[[1]]; alt <- strsplit(a[2], ",")[[1]]; groups <- a[-(1:2)]
    norm <- function(f) {
        if (!file.exists(f)) return(NULL)
        l <- readLines(f, warn = FALSE, encoding = "bytes")
        h <- grep("user +system +elapsed", l)
        if (length(h)) l <- l[-c(h, h + 1L)]
        ## byte-wise: outputs need not be valid in the session's encoding
        l <- gsub('0x[0-9a-fA-F]+|<[0-9A-F]{8,16}>|"[0-9a-f]{16}"', "ADDR", l, useBytes = TRUE)
        l <- gsub("C:([/\\\\]+)R-o3", "C:\\1R", l, useBytes = TRUE)   # the copy with the -O3 BLAS
        ## timings the test frameworks print, which a faster BLAS changes
        ## systematically: tinytest's "12 tests OK 92ms" and "(1.3s)",
        ## testthat's "[ FAIL 0 | ... ]" summary line; and gc()'s table
        l <- gsub("([0-9]+ tests( OK| FAILED)?|All ok, [0-9]+ results) \\(?[0-9.]+m?s\\)?", "\\1 TIME", l, useBytes = TRUE)
        l <- l[!grepl("^(Ncells|Vcells) +[0-9]", l, useBytes = TRUE)]
        ## widths of columns follow their widest entry, a path or a timing
        gsub(" +", " ", trimws(l, "right"), useBytes = TRUE)
    }
    dir <- function(r, g) file.path(work, paste0("out-", r), g)
    ## the output of file f in run r: its lines and whether the run failed
    ## (R CMD BATCH left f.Rout.fail), or NULL when there is neither
    read <- function(r, g, f) {
        for (ext in c("", ".fail")) {
            l <- norm(file.path(dir(r, g), paste0(f, ext)))
            if (!is.null(l)) return(list(lines = l, failed = ext == ".fail"))
        }
        NULL
    }
    ## one of "same", "differ", "failed", "missing", "unstable" for output f:
    ## "same" when every run agrees on every line, "differ" when the runs of
    ## each set agree on a line and the sets do not (or one set failed and the
    ## other did not), "unstable" when the runs of a set disagree on a line or
    ## on failing without a stable difference, "failed" when every run failed
    one <- function(g, f, ref, alt) {
        R <- lapply(ref, read, g, f); A <- lapply(alt, read, g, f)
        miss <- c(ref, alt)[vapply(c(R, A), is.null, NA)]
        if (length(miss)) {
            cat(sprintf("  %s: missing in %s\n", f, paste(miss, collapse = ", ")))
            return("missing")
        }
        fr <- vapply(R, `[[`, NA, "failed"); fa <- vapply(A, `[[`, NA, "failed")
        if (any(fr) || any(fa)) {
            cat(sprintf("  %s: failed in %s\n", f, paste(c(ref[fr], alt[fa]), collapse = ", ")))
            if (any(fr) != all(fr) || any(fa) != all(fa)) return("unstable")
            if (all(fr) != all(fa)) return("differ")
        }
        R <- lapply(R, `[[`, "lines"); A <- lapply(A, `[[`, "lines")
        n <- lengths(c(R, A)); nr <- n[seq_along(R)]; na <- n[-seq_along(R)]
        if (length(unique(nr)) > 1 || length(unique(na)) > 1) return("unstable")
        if (nr[1] != na[1]) {
            cat(sprintf("  %s: %d lines in %s, %d in %s\n", f, nr[1], ref[1], na[1], alt[1]))
            return("differ")
        }
        same <- function(L) Reduce(`&`, lapply(L[-1], function(l) l == L[[1]]), rep(TRUE, n[1]))
        sR <- same(R); sA <- same(A)
        d <- which(sR & sA & R[[1]] != A[[1]])
        if (length(d)) {
            cat(sprintf("  %s: %d stable lines differ\n", f, length(d)))
            ## bytes: substr() refuses strings in the "bytes" encoding
            head100 <- function(x) rawToChar(head(charToRaw(x), 100))
            for (k in head(d, 3))
                cat(sprintf("    %s: %s\n    %s: %s\n", ref[1], head100(R[[1]][k]), alt[1], head100(A[[1]][k])))
            return("differ")
        }
        if (all(fr)) "failed" else if (all(sR & sA)) "same" else "unstable"
    }
    kinds <- c("same", "differ", "failed", "missing", "unstable")
    if (!length(groups))
        groups <- list.dirs(file.path(work, paste0("out-", ref[1])), full.names = FALSE, recursive = FALSE)
    total <- setNames(integer(length(kinds)), kinds)
    for (g in groups) {
        files <- sort(unique(sub("\\.fail$", "", unlist(lapply(c(ref, alt), function(r)
            list.files(dir(r, g), "\\.Rout(\\.fail)?$", recursive = TRUE))))))
        k <- vapply(files, function(f) tryCatch(one(g, f, ref, alt), error = function(e) {
            cat(sprintf("  %s: not compared: %s\n", f, conditionMessage(e))); "missing" }), "")
        n <- table(factor(k, kinds))
        total <- total + n
        ## "failed" is a failure in every run, so not a difference
        cat(sprintf("== %-12s %3d output files: %3d same, %3d differ in %s, %3d failed, %3d missing, %3d unstable\n",
                    g, length(files), n["same"], n["differ"], paste(alt, collapse = "+"), n["failed"], n["missing"],
                    n["unstable"]))
    }
    cat(sprintf("total %d output files: %s\n", sum(total), paste(total, names(total), collapse = ", ")))
}

## Compare the output of examples and tests between runs of a reference and
## runs of an alternative, as R CMD check compares output with .Rout.save:
##   Rscript compare-runs.R [options] REF1,REF2.. ALT1,.. GROUP...
## Each run is a directory template in which %s stands for the group (a
## package, or "recommended"), and is named by the directory that holds
## the group's; its *.Rout and *.Rout.fail files, recursively, are the
## outputs. Options:
##   --home=PATH    an R.home() of a run, which prints as R_HOME
##   --drop=REGEX   text left out of every line (a difference by design)
##   --only=REGEX   only outputs whose relative path matches
##   --need=NAME    an output every run must have (%s for the group)
##   --blank        blank addresses, timings and gc() tables first, for
##                  runs whose speed differs by design
##   --fail         exit 1 when an output differs or is missing, or the
##                  alternative fails an output a reference run passes
## The run's own directory and its name are replaced first, in any of the
## spellings of a path. tools::Rdiff then compares the first reference run
## with every other run, with the first run on the left, so that the line
## numbers of all diffs agree. A difference is a hunk, or one line of a
## hunk that changes as many lines as it replaces. It is noise when a
## reference run changes the same line, or adds or removes as many lines at
## the same place, or when it is the line after the header of system.time().
## An output is
##   differ    when every alternative run has the same difference that is
##             not noise, or the alternative runs all fail and the
##             reference runs do not, or the other way round;
##   failed    when every run failed (R left a .Rout.fail) without that;
##   same      when no run differs from the first at all;
##   unstable  otherwise: some run differs, but not stably;
##   missing   when a run lacks it.
## Prints the class of every output that is not the same, with up to
## $COMPARE_DETAIL (3) differences, a line per group, and the counts per
## group to compare.tsv.

a <- commandArgs(TRUE)
opt <- function(name) sub(sprintf("^--%s=", name), "", grep(sprintf("^--%s=", name), a, value = TRUE))
homes <- opt("home"); drops <- opt("drop"); only <- opt("only"); need <- opt("need")
blank <- "--blank" %in% a; fail <- "--fail" %in% a
a <- grep("^--", a, value = TRUE, invert = TRUE)
ref <- strsplit(a[1], ",")[[1]]; alt <- strsplit(a[2], ",")[[1]]; groups <- a[-(1:2)]
detail <- suppressWarnings(as.integer(Sys.getenv("COMPARE_DETAIL", "3")))
if (is.na(detail) || detail < 0) stop("COMPARE_DETAIL is not a count")
## Rdiff falls back to its own comparison without diff, whose output has
## no hunks, and diff exits 2 on trouble
if (!nzchar(Sys.which("diff"))) stop("no diff on the PATH")
dir <- function(run, g) if (grepl("%s", run, fixed = TRUE)) sub("%s", g, run, fixed = TRUE) else file.path(run, g)
name <- function(run) basename(dirname(dir(run, "x")))

## the spellings of a path: / or \, and \ doubled as deparse() prints it
spellings <- function(p) {
    p <- gsub("\\\\", "/", p)
    unique(c(p, gsub("/", "\\\\", p), gsub("/", "\\\\\\\\", p)))
}
norm <- function(l, rundir) {
    ## byte-wise: outputs need not be valid in the session's encoding
    for (p in spellings(normalizePath(rundir, winslash = "/", mustWork = FALSE)))
        l <- gsub(p, "RUNDIR", l, fixed = TRUE, useBytes = TRUE)
    l <- gsub(basename(dirname(rundir)), "RUN", l, fixed = TRUE, useBytes = TRUE)
    ## the longest first, so that C:/R-o3 is not taken for C:/R
    for (h in homes[order(-nchar(homes))]) for (p in spellings(h)) l <- gsub(p, "R_HOME", l, fixed = TRUE, useBytes = TRUE)
    for (d in drops) l <- gsub(d, "", l, perl = TRUE, useBytes = TRUE)
    if (!blank) return(l)
    l <- gsub('0x[0-9a-fA-F]+|<[0-9A-F]{8,16}>|"[0-9a-f]{16}"', "ADDR", l, useBytes = TRUE)
    ## timings the test frameworks print, which a faster BLAS changes
    ## systematically: tinytest's "12 tests OK 92ms" and "(1.3s)",
    ## testthat's summary line
    l <- gsub("([0-9]+ tests( OK| FAILED)?|All ok, [0-9]+ results) \\(?[0-9.]+m?s\\)?", "\\1 TIME", l, useBytes = TRUE)
    ## timings packages print: a number with a unit of time, and the
    ## numbers on a line that announces one; a bare number stays, since
    ## nothing says it is a time
    l <- gsub("\\b[0-9]+(\\.[0-9]+)?(e[-+]?[0-9]+)? ?(s|sec|secs|seconds?|ms|min|mins|minutes?|h|hours?|CPU-s|elapsed-s)\\b",
              "TIME \\3", l, useBytes = TRUE, perl = TRUE)
    t <- grepl("(?i)\\b(time elapsed|elapsed time|elapsed|CPU time|run time|time required|took|time_use|time =|time:|timing)",
               l, perl = TRUE, useBytes = TRUE)
    l[t] <- gsub("\\b[0-9]+(\\.[0-9]+)?(e[-+]?[0-9]+)?\\b", "TIME", l[t], useBytes = TRUE, perl = TRUE)
    l[!grepl("^(Ncells|Vcells) +[0-9]", l, useBytes = TRUE)]
}
## the output f of a run, normalised into a file of its own, and whether
## the run failed; NULL when there is neither f nor f.fail
read <- function(run, g, f) {
    for (ext in c("", ".fail")) {
        p <- file.path(dir(run, g), paste0(f, ext))
        if (file.exists(p)) {
            n <- tempfile(fileext = ".Rout")
            writeLines(norm(readLines(p, warn = FALSE, encoding = "bytes"), dir(run, g)), n, useBytes = TRUE)
            return(list(file = n, failed = ext == ".fail"))
        }
    }
    NULL
}
rdiff <- function(from, to, forEx) {
    r <- tools::Rdiff(from, to, useDiff = TRUE, forEx = forEx, Log = TRUE)
    if (r$status > 1L) stop("diff failed: ", paste(r$out, collapse = "\n"))
    ## every byte a character, so that the regular expressions below take
    ## output that is not valid in the session's encoding
    iconv(r$out, "latin1", "UTF-8")
}
## The differences of a diff: each line of a hunk that changes as many
## lines as it replaces, since diff joins neighbouring changes into one
## hunk, and every other hunk whole. at: the left lines, kind and number
## of right lines, which all diffs share; changed: the left lines a change
## covers; what: the change, with blanks squeezed as diff -bw compares.
diffs <- function(out) {
    h <- grep("^[0-9]+(,[0-9]+)?[acd][0-9]+(,[0-9]+)?$", out)
    sq <- function(x) gsub("[[:space:]]+", " ", trimws(x))
    unlist(lapply(seq_along(h), function(k) {
        body <- out[seq(h[k] + 1L, if (k < length(h)) h[k + 1L] - 1L else length(out))]
        l <- sub("^< ", "", grep("^< ", body, value = TRUE)); r <- sub("^> ", "", grep("^> ", body, value = TRUE))
        lr <- as.integer(strsplit(sub("[acd].*", "", out[h[k]]), ",")[[1]])
        kind <- sub("^[0-9,]+([acd]).*", "\\1", out[h[k]])
        if (kind == "c" && length(l) == length(r))
            return(lapply(seq_along(l), function(i) {
                n <- lr[1] + i - 1L
                list(at = paste0(n, "c 1"), line = TRUE, changed = n, what = paste(n, sq(l[i]), "->", sq(r[i])),
                     show = c(sprintf("line %d: %s", n, l[i]), paste("->", r[i])))
            }))
        list(list(at = paste(sub("[0-9,]+$", "", out[h[k]]), length(r)), line = FALSE,
                  changed = if (kind == "c") seq(lr[1], lr[length(lr)]) else integer(),
                  what = paste(c(sub("[0-9,]+$", "", out[h[k]]), sq(r)), collapse = "\n"),
                  show = c(out[h[k]], sprintf("< %s", l), sprintf("> %s", r))))
    }), recursive = FALSE)
}
show <- function(x) cat(sprintf("    %s\n", x$show[1]), if (length(x$show) > 1) sprintf("    %s\n", x$show[-1]), sep = "")
altfailed <- FALSE

one <- function(g, f) {
    R <- lapply(ref, read, g, f); A <- lapply(alt, read, g, f)
    miss <- c(ref, alt)[vapply(c(R, A), is.null, NA)]
    if (length(miss)) {
        cat(sprintf("  %s: missing in %s\n", f, paste(vapply(miss, name, ""), collapse = ", ")))
        return("missing")
    }
    fr <- vapply(R, `[[`, NA, "failed"); fa <- vapply(A, `[[`, NA, "failed")
    if (any(fr) || any(fa)) {
        cat(sprintf("  %s: failed in %s\n", f, paste(vapply(c(ref[fr], alt[fa]), name, ""), collapse = ", ")))
        if (any(fa) && !all(fr)) altfailed <<- TRUE
        if (any(fr) == all(fr) && any(fa) == all(fa) && all(fr) != all(fa)) return("differ")
    }
    forEx <- grepl("-Ex\\.Rout$", f)
    base <- R[[1]]$file
    dr <- lapply(R[-1], function(x) diffs(rdiff(base, x$file, forEx)))
    da <- lapply(A, function(x) diffs(rdiff(base, x$file, forEx)))
    noise <- unlist(lapply(dr, function(d) vapply(d, `[[`, "", "at")))
    changed <- unlist(lapply(dr, function(d) unlist(lapply(d, `[[`, "changed"))))
    ## the line after the header of system.time() and proc.time() in the
    ## first run as Rdiff cleans it, which two runs can print alike by chance
    empty <- tempfile(); file.create(empty)
    clean <- sub("^< ", "", rdiff(base, empty, forEx)[-1])
    changed <- c(changed, grep("^ *user +system +elapsed *$", clean) + 1L)
    counts <- function(x) !(x$at %in% noise) && !(x$line && x$changed %in% changed)
    count <- lapply(da, Filter, f = counts)
    stable <- Reduce(intersect, lapply(count, function(d) vapply(d, `[[`, "", "what")))
    if (length(stable)) {
        cat(sprintf("  %s: %d stable differences\n", f, length(stable)))
        for (x in head(Filter(function(x) x$what %in% stable, count[[1]]), detail)) show(x)
        return("differ")
    }
    if (all(fr) && all(fa)) return("failed")
    u <- unlist(c(dr, da), recursive = FALSE)
    if (!length(u) && !any(fr) && !any(fa)) return("same")
    cat(sprintf("  %s: %d unstable differences\n", f, length(u)))
    for (x in head(u, detail)) show(x)
    "unstable"
}

kinds <- c("same", "differ", "failed", "missing", "unstable")
total <- setNames(integer(length(kinds)), kinds)
rows <- list()
for (g in groups) {
    files <- sort(unique(sub("\\.fail$", "", unlist(lapply(c(ref, alt), function(r)
        list.files(dir(r, g), "\\.Rout(\\.fail)?$", recursive = TRUE))))))
    for (o in only) files <- grep(o, files, value = TRUE)
    files <- sort(unique(c(files, sub("%s", g, need, fixed = TRUE))))
    k <- vapply(files, function(f) tryCatch(one(g, f), error = function(e) {
        cat(sprintf("  %s: not compared: %s\n", f, conditionMessage(e))); "missing" }), "")
    n <- table(factor(k, kinds))
    total <- total + n
    rows[[g]] <- data.frame(package = g, files = length(files), t(c(n)))
    cat(sprintf("== %-12s %3d output files: %3d same, %3d differ in %s, %3d failed, %3d missing, %3d unstable\n",
                g, length(files), n["same"], n["differ"], paste(vapply(alt, name, ""), collapse = "+"), n["failed"],
                n["missing"], n["unstable"]))
}
cat(sprintf("total %d output files: %s\n", sum(total), paste(total, names(total), collapse = ", ")))
tsv <- do.call(rbind, c(list(data.frame(package = character(), files = integer(), t(total)[0, , drop = FALSE])), rows))
write.table(tsv, "compare.tsv", sep = "\t", quote = FALSE, row.names = FALSE)
if (fail && (total["differ"] > 0 || total["missing"] > 0 || altfailed)) quit(status = 1)

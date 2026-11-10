## Differences in the output of examples or tests between CRAN's R and the
## built R that are neither noise nor by design:
##   Rscript compare-output.R REF1 REF2 OUR FOREX REFHOME OURHOME
## REF1 and REF2 are two runs of CRAN's R, OUR the run of the built R, FOREX
## TRUE for example output, REFHOME and OURHOME R.home() of each, with "/".
## tools::Rdiff compares REF1 with REF2 and REF1 with OUR, as R CMD check
## compares output with .Rout.save, and gives both diffs with the cleaned
## REF1 on the left, so their line numbers agree.  A changed line of OUR is
## noise when REF2 changes the same line of REF1 too: timings, temporary
## files and their times, installation times; so is the line after the
## header of system.time() and proc.time(), whose timings two runs can
## print alike by chance; an added or removed block
## when REF2 adds or removes as many lines at the same place.  A changed
## line is by design when it is the line of REF1 with only what differs
## between the two installations changed: R.home(), the check directory
## (chk-ref1 against chk-our), and sessionInfo() naming the FlexiBLAS
## backend before the LAPACK version (patches/r/0002).  Prints both diffs and the differences that count;
## exits 1 when any does.

a <- commandArgs(TRUE)
forEx <- as.logical(a[4]); refhome <- a[5]; ourhome <- a[6]
## Rdiff falls back to its own comparison without diff, whose output has
## no hunks, and diff exits 2 on trouble
if (!nzchar(Sys.which("diff"))) stop("no diff on the PATH")
rdiff <- function(from, to) {
    r <- tools::Rdiff(from, to, useDiff = TRUE, forEx = forEx, Log = TRUE)
    if (r$status > 1L) stop("diff failed: ", paste(r$out, collapse = "\n"))
    r$out
}

## the hunks of a diff: header fields and the lines of each side
hunks <- function(out) {
    h <- grep("^[0-9]+(,[0-9]+)?[acd][0-9]+(,[0-9]+)?$", out)
    lapply(seq_along(h), function(k) {
        body <- out[seq(h[k] + 1L, if (k < length(h)) h[k + 1L] - 1L else length(out))]
        list(head = out[h[k]],
             left = sub("^< ", "", grep("^< ", body, value = TRUE)),
             right = sub("^> ", "", grep("^> ", body, value = TRUE)))
    })
}
## the left range and kind of a header, which both diffs share, and the
## number of right lines
key <- function(x) paste(sub("[0-9,]+$", "", x$head), length(x$right))

d12 <- rdiff(a[1], a[2]); d13 <- rdiff(a[1], a[3])
cat("ref1 against ref2:\n"); writeLines(d12)
cat("ref1 against the built R:\n"); writeLines(d13)

## the lines of REF1 that REF2 changes, and the other hunks of REF2 by key
h12 <- hunks(d12)
left <- function(x) {
    r <- as.integer(strsplit(sub("[acd].*", "", x$head), ",")[[1]])
    seq(r[1], r[length(r)])
}
changed <- unlist(lapply(Filter(function(x) grepl("c", x$head), h12), left))
## and the lines of system.time() and proc.time() in REF1 as Rdiff cleans
## it, which two runs can print alike by chance
empty <- tempfile(); file.create(empty)
ref <- sub("^< ", "", rdiff(a[1], empty)[-1])
changed <- c(changed, grep("^ *user +system +elapsed *$", ref) + 1L)
noise <- vapply(h12, key, "")
## a line of OUR that is the line of REF1 with only what differs between
## the two installations changed
bydesign <- function(l, r) {
    ## as diff -bw, which Rdiff uses, compares them
    l <- gsub("[[:space:]]+", " ", trimws(l)); r <- gsub("[[:space:]]+", " ", trimws(r))
    r == gsub("chk-ref1", "chk-our", gsub(refhome, ourhome, l, fixed = TRUE), fixed = TRUE) |
        r == paste("BLAS/LAPACK: FlexiBLAS NETLIB;", l)
}
## a change of as many lines is judged line by line, since diff joins
## neighbouring changes into one hunk; other hunks only as a whole
counts <- function(x) {
    if (key(x) %in% noise) return(FALSE)
    if (!grepl("c", x$head) || length(x$left) != length(x$right)) return(TRUE)
    any(!(left(x) %in% changed) & !bydesign(x$left, x$right))
}
count <- Filter(counts, hunks(d13))
cat("differences that count:", length(count), "\n")
for (x in count) writeLines(c(x$head, sprintf("< %s", x$left), sprintf("> %s", x$right)))
quit(status = as.integer(length(count) > 0))

#!/bin/bash
# The verdict of compare-optflags.R comparisons, from the rows of one or
# more compare.tsv files (package, files, same, differ, failed, missing,
# unstable; header lines and CRs skipped), as one line: "D of F files differ
# in P packages", "no difference: S of F files the same (U unstable, M
# missing, X failed)", or "nothing compared" when no file was the same and
# none differed.
#   tests/optflags-verdict.sh compare.tsv
cat "$@" 2>/dev/null | tr -d '\r' | awk -F'\t' '
    $1 == "package" {next}
    {f += $2; s += $3; d += $4; x += $5; m += $6; u += $7}
    $4 > 0 {p++}
    END {
        if (d) printf "%d of %d files differ in %d packages\n", d, f, p
        else if (s) printf "no difference: %d of %d files the same (%d unstable, %d missing, %d failed)\n", s, f, u, m, x
        else print "nothing compared"
    }'

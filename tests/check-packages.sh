#!/bin/bash
# R CMD check of CRAN source packages, as the CRAN daily checks run it,
# under the built R and under CRAN's build of the same R, to show that the
# FlexiBLAS build gives a package nothing that R itself does not:
#   check-packages.sh REFBIN BIN PACKAGE...
# REFBIN and BIN are the directories with R.exe.  The reference checks the
# same tarballs, downloaded once, twice (chk-ref1, chk-ref2), the built R
# once with its default backend, NETLIB (chk-our), and once with
# OPENBLAS-OPENMP (chk-omp).  An item that did not end in OK counts when a
# run of the built R has it and neither reference run does.  The output of
# examples and tests, which raises no NOTE when it differs, counts where
# NETLIB's differs beyond noise and design (compare-runs.R); OpenBLAS's
# results differ from R's own in the last bits, so its output differences
# are only reported.  Exits 1 when an item or a NETLIB output difference
# counts, or a check did not finish.
refbin=$1 bin=$2; shift 2
# without --as-cran, so the examples run without timings, as for the
# .Rout.save that tools::Rdiff expects to compare with
export LC_ALL=C MAKEFLAGS=-j2 _R_CHECK_FORCE_SUGGESTS_=false
for r in "$refbin" "$bin"; do
    echo "$r: $("$r/Rscript" -e 'cat(R.version.string)')"
done
mkdir -p src
"$bin/Rscript" -e 'download.packages(commandArgs(TRUE), "src", repos = "https://cloud.r-project.org", type = "source")' "$@" > /dev/null || exit 1
for p in "$@"; do
    ls src/${p}_*.tar.gz > /dev/null || { echo "no source for $p"; exit 1; }
done
check() {   # check NAME RBIN: all packages, one after the other
    mkdir -p chk-$1
    for t in src/*.tar.gz; do
        p=$(basename $t); p=${p%%_*}
        (cd chk-$1 && "$2/R" CMD check --no-manual --ignore-vignettes "../$t" > $p.out 2>&1)
    done
}
# ref2 a minute later, so that times to the second or minute printed by
# both reference runs differ and drop out
check ref1 "$refbin" & { sleep 61; check ref2 "$refbin"; } & FLEXIBLAS=NETLIB check our "$bin" &
FLEXIBLAS=OPENBLAS-OPENMP check omp "$bin" & wait
status=0
for r in ref1 ref2 our omp; do
    : > items-$r.raw
    for p in "$@"; do
        log=chk-$r/$p.Rcheck/00check.log
        [ -f $log ] || { echo "$r $p: no 00check.log"; status=1; continue; }
        grep -q '^Status:' $log || { echo "$r $p: check did not finish"; status=1; }
        # the items, without timings and line endings
        grep -E '^\* checking .* (NOTE|WARNING|ERROR)[[:space:]]*$' $log | tr -d '\r' |
            sed -e 's/ \[[^]]*\]//' -e "s/^/$p: /" >> items-$r.raw
    done
    sort -o items-$r.txt items-$r.raw
done
for r in ref1 ref2 our omp; do echo "$r:"; sed 's/^/  /' items-$r.txt; done
for r in our omp; do
    new=$(comm -13 <(sort -u items-ref1.txt items-ref2.txt) items-$r.txt)
    echo "items only in the built R ($r): ${new:-none}"
    # what each such item says in the 00check.log of that run
    echo "$new" | grep . | while IFS= read -r l; do
        p=${l%%: *}; item=${l#*: }
        echo "  $l:"
        tr -d '\r' < chk-$r/$p.Rcheck/00check.log | sed 's/ \[[^]]*\]//' |
            awk -v it="$item" 'f && /^\* /{exit} f; $0 == it {f=1}' | sed 's/^/    /'
    done
    [ -z "$new" ] || status=1
done
# the output of examples and tests, compared by tools::Rdiff as R CMD
# check compares output with .Rout.save, with what varies between the two
# reference runs and what differs between the installations by design left
# out: R.home(), the check directory, and sessionInfo() naming the FlexiBLAS
# backend before the LAPACK version (patches/r/0002) (compare-runs.R)
home() { "$1/Rscript" -e 'cat(normalizePath(R.home(), "/"))'; }
echo "output of examples and tests, NETLIB:"
COMPARE_DETAIL=1000 "$bin/Rscript" "$(dirname "$0")/compare-runs.R" --fail --need=%s-Ex.Rout --home="$(home "$refbin")" --home="$(home "$bin")" \
    --drop='BLAS/LAPACK: FlexiBLAS [A-Z-]+; *' --only='^([^/]+-Ex|tests/[^/]+)\.Rout$' \
    'chk-ref1/%s.Rcheck,chk-ref2/%s.Rcheck' 'chk-our/%s.Rcheck' "$@" || status=1
echo "output of examples and tests, OPENBLAS-OPENMP (reported only):"
COMPARE_DETAIL=1000 "$bin/Rscript" "$(dirname "$0")/compare-runs.R" --need=%s-Ex.Rout --home="$(home "$refbin")" --home="$(home "$bin")" \
    --drop='BLAS/LAPACK: FlexiBLAS [A-Z-]+; *' --only='^([^/]+-Ex|tests/[^/]+)\.Rout$' \
    'chk-ref1/%s.Rcheck,chk-ref2/%s.Rcheck' 'chk-omp/%s.Rcheck' "$@" || status=1
exit $status

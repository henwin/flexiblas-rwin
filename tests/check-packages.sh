#!/bin/bash
# R CMD check --as-cran of CRAN source packages under the built R and
# under CRAN's build of the same R, to show that the FlexiBLAS build gives
# a package no NOTE, WARNING or ERROR that R itself does not:
#   check-packages.sh REFBIN BIN PACKAGE...
# REFBIN and BIN are the directories with R.exe.  Each R checks the same
# tarballs, downloaded once, in a directory of its own (chk-ref, chk-our),
# with the default backend of the built R.  Prints the revision of each R,
# per R every check item that did not end in OK, and how many lines of the
# example output differ, timings left out (a report, not a verdict); exits
# 1 when the built R has an item the reference does not, or a check did
# not finish.
refbin=$1 bin=$2; shift 2
export LC_ALL=C MAKEFLAGS=-j2 _R_CHECK_CRAN_INCOMING_=false \
    _R_CHECK_CRAN_INCOMING_REMOTE_=false _R_CHECK_FORCE_SUGGESTS_=false \
    _R_CHECK_SYSTEM_CLOCK_=false
for r in "$refbin" "$bin"; do
    echo "$r: $("$r/Rscript" -e 'cat(R.version.string, "r", R.version[["svn rev"]])')"
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
        (cd chk-$1 && "$2/R" CMD check --as-cran --no-manual --ignore-vignettes "../$t" > $p.out 2>&1)
    done
}
check ref "$refbin" & check our "$bin" & wait
status=0
for r in ref our; do
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
for r in ref our; do echo "$r:"; sed 's/^/  /' items-$r.txt; done
new=$(comm -13 items-ref.txt items-our.txt)
echo "only in the built R: ${new:-none}"
[ -z "$new" ] || status=1
norm() {   # example output without what differs between any two runs:
           # the R version line, the time at the end, the output of
           # system.time() and proc.time() (the header and the line after
           # it, so other lines of three numbers stay), and addresses
    tr -d '\r' | sed -e '/^R Under development\|^R version/d' \
        -e '/^Time elapsed:/d' \
        -e '/^ *user \+system \+elapsed *$/{N;d}' \
        -e 's/0x[0-9a-f]\+/0x/g'
}
echo "example output, lines that differ (version, timings and addresses left out):"
for p in "$@"; do
    a=chk-ref/$p.Rcheck/$p-Ex.Rout b=chk-our/$p.Rcheck/$p-Ex.Rout
    if [ -f $a ] && [ -f $b ]; then
        diff <(norm < $a) <(norm < $b) > ex-$p.diff
        echo "  $p: $(grep -c '^[<>]' ex-$p.diff)"
        head -20 ex-$p.diff | sed 's/^/    /'
    else
        echo "  $p: no example output to compare"
    fi
done
exit $status

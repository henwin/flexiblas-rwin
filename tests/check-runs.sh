#!/bin/bash
# R CMD check of CRAN source packages in several runs, and tools::Rdiff of
# every output of the first run against the same output of each other run,
# printed in full; the review is separate:
#   check-runs.sh NAME=RBIN[,VAR=VALUE...] ... -- PACKAGE...
# RBIN is a directory with R.exe; the VAR=VALUE pairs are set for that run
# only.  The tarballs are downloaded once.  Exits 1 when a check did not
# run to its end (no Status line in 00check.log), since then there is
# nothing to show.
runs=()
while [ $# -gt 0 ] && [ "$1" != -- ]; do runs+=("$1"); shift; done
shift
first=${runs[0]#*=}; first=${first%%,*}
# without --as-cran, so the examples run without timings, as for the
# .Rout.save that tools::Rdiff expects to compare with; R CMD check stops
# each step after _R_CHECK_ELAPSED_TIMEOUT_, here 30 minutes unless set
# (R's default is no limit), so that a package that hangs ends as an ERROR
export LC_ALL=C MAKEFLAGS=-j2 _R_CHECK_FORCE_SUGGESTS_=false _R_CHECK_ELAPSED_TIMEOUT_=${_R_CHECK_ELAPSED_TIMEOUT_:-30m}
mkdir -p src
"$first/Rscript" -e 'download.packages(commandArgs(TRUE), "src", repos = "https://cloud.r-project.org", type = "source")' "$@" > /dev/null || exit 1
for p in "$@"; do
    ls src/${p}_*.tar.gz > /dev/null || { echo "no source for $p"; exit 1; }
done
check() {   # check NAME RBIN: every package, one after the other
    mkdir -p chk-$1
    for t in src/*.tar.gz; do
        p=$(basename $t); p=${p%%_*}
        (cd chk-$1 && "$2/R" CMD check --no-manual --ignore-vignettes "../$t" > $p.out 2>&1)
    done
}
names=()
for r in "${runs[@]}"; do
    name=${r%%=*} spec=${r#*=}
    bin=${spec%%,*} vars=(); [ "$spec" = "$bin" ] || IFS=, read -ra vars <<< "${spec#*,}"
    names+=("$name")
    echo "$name: $("$bin/Rscript" -e 'cat(R.version.string)') ${vars[*]}"
    env "${vars[@]}" bash -c "$(declare -f check); check $name '$bin'" &
done
wait
status=0
for p in "$@"; do
    for n in "${names[@]}"; do
        log=chk-$n/$p.Rcheck/00check.log
        st=$(tr -d '\r' < $log 2>/dev/null | grep '^Status:')
        echo "$n $p: ${st:-check did not finish}"
        [ -n "$st" ] || status=1
    done
done
"$first/Rscript" "$(dirname "$0")/rdiff-runs.R" "${names[@]/#/chk-}" -- "$@"
exit $status

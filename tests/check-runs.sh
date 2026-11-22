#!/bin/bash
# R CMD check of CRAN source packages in several runs, and tools::Rdiff of
# every output of the first run against the same output of each other run,
# printed in full; the review is separate:
#   check-runs.sh NAME=RBIN[,VAR=VALUE...] ... -- PACKAGE...
# RBIN is a directory with R.exe; the VAR=VALUE pairs are set for that run
# only.  The tarballs are downloaded once.  The output of R CMD check and
# 00install.out of the first run, and the output of R CMD check of any
# run that did not run to its end, are printed in full too, so that what
# every run shares, and where a check stopped, can be read.  Each run has
# its own R_USER_CACHE_DIR, R_USER_DATA_DIR and R_USER_CONFIG_DIR, since
# the runs are concurrent and packages keep caches there.  Exits 1 when a
# check did not run to its end (no Status line in 00check.log).  On
# GitHub, workflow commands are off while it prints, so that no line of
# the output is taken for one.
[ -z "$GITHUB_ACTIONS" ] || { tok=stop$RANDOM$RANDOM; echo "::stop-commands::$tok"; trap "echo; echo '::$tok::'" EXIT; }
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
    u=$PWD/chk-$name/user; mkdir -p "$u"/cache "$u"/data "$u"/config
    ! command -v cygpath > /dev/null || u=$(cygpath -m "$u")
    vars=("R_USER_CACHE_DIR=$u/cache" "R_USER_DATA_DIR=$u/data" "R_USER_CONFIG_DIR=$u/config" "${vars[@]}")
    echo "$name: $("$bin/Rscript" -e 'cat(R.version.string)') ${vars[*]}"
    env "${vars[@]}" bash -c "$(declare -f check); check $name '$bin'" &
done
wait
status=0 stopped=()
for p in "$@"; do
    for n in "${names[@]}"; do
        log=chk-$n/$p.Rcheck/00check.log
        st=$(tr -d '\r' 2>/dev/null < "$log" | grep '^Status:')
        echo "$n $p: ${st:-check did not finish}"
        [ -n "$st" ] || { status=1; stopped+=("chk-$n/$p.out"); }
    done
done
show() { [ ! -f "$1" ] || { echo "== $2: $1"; tr -d '\r' < "$1"; [ -z "$(tail -c1 "$1")" ] || echo; }; }
for p in "$@"; do
    show "chk-${names[0]}/$p.out" $p; show "chk-${names[0]}/$p.Rcheck/00install.out" $p
done
for f in "${stopped[@]}"; do
    [ "${f%%/*}" = "chk-${names[0]}" ] || { p=${f##*/}; show "$f" ${p%.out}; }
done
"$first/Rscript" "$(dirname "$0")/rdiff-runs.R" "${names[@]/#/chk-}" -- "$@"
exit $status

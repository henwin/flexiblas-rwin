#!/bin/bash
# R CMD check --as-cran of CRAN source packages under the built R and
# under CRAN's build of the same R, to show that the FlexiBLAS build gives
# a package nothing that R itself does not:
#   check-packages.sh REFBIN BIN PACKAGE...
# REFBIN and BIN are the directories with R.exe.  The reference checks the
# same tarballs, downloaded once, twice (chk-ref1, chk-ref2), the built R
# once (chk-our), with its default backend.  An item that did not end in
# OK counts when the built R has it and neither reference run does.  The
# output of examples and tests, which raises no NOTE when it differs, is
# compared with tools::Rdiff and printed.  Exits 1 when an item counts or
# a check did not finish.
refbin=$1 bin=$2; shift 2
export LC_ALL=C MAKEFLAGS=-j2 _R_CHECK_CRAN_INCOMING_=false \
    _R_CHECK_CRAN_INCOMING_REMOTE_=false _R_CHECK_FORCE_SUGGESTS_=false \
    _R_CHECK_SYSTEM_CLOCK_=false
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
        (cd chk-$1 && "$2/R" CMD check --as-cran --no-manual --ignore-vignettes "../$t" > $p.out 2>&1)
    done
}
# ref2 a minute later, so that times to the second or minute printed by
# both reference runs differ and drop out
check ref1 "$refbin" & { sleep 61; check ref2 "$refbin"; } & check our "$bin" & wait
status=0
for r in ref1 ref2 our; do
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
for r in ref1 ref2 our; do echo "$r:"; sed 's/^/  /' items-$r.txt; done
new=$(comm -13 <(sort -u items-ref1.txt items-ref2.txt) items-our.txt)
echo "items only in the built R: ${new:-none}"
[ -z "$new" ] || status=1
# the output of examples and tests, compared as R CMD check compares output
# with .Rout.save, by tools::Rdiff (forEx for examples): the reference with
# itself, which shows what varies between runs, and with the built R; both
# printed in full.  Reported, not decided, until the noise is settled from
# these.
rdiff() {   # rdiff FROM TO FOREX
    "$bin/Rscript" -e 'a <- commandArgs(TRUE); invisible(tools::Rdiff(a[1], a[2], useDiff = TRUE, forEx = as.logical(a[3])))' "$1" "$2" "$3"
}
echo "output of examples and tests, tools::Rdiff:"
for p in "$@"; do
    for f in $p-Ex.Rout $(for r in ref1 our; do (cd chk-$r/$p.Rcheck 2> /dev/null && ls tests/*.Rout 2> /dev/null); done | sort -u); do
        a=chk-ref1/$p.Rcheck/$f b=chk-ref2/$p.Rcheck/$f c=chk-our/$p.Rcheck/$f
        ex=FALSE; [ $f = $p-Ex.Rout ] && ex=TRUE
        if [ -f $a ] && [ -f $b ] && [ -f $c ]; then
            echo "== $p $f, ref1 against ref2:"; rdiff $a $b $ex
            echo "== $p $f, ref1 against the built R:"; rdiff $a $c $ex
        else
            echo "== $p $f: not in every run"
            status=1
        fi
    done
done
exit $status

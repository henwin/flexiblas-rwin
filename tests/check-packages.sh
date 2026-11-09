#!/bin/bash
# R CMD check --as-cran of CRAN source packages under the built R and
# under CRAN's build of the same R, to show that the FlexiBLAS build gives
# a package nothing that R itself does not:
#   check-packages.sh REFBIN BIN PACKAGE...
# REFBIN and BIN are the directories with R.exe.  The reference checks the
# same tarballs, downloaded once, twice (chk-ref1, chk-ref2), the built R
# once (chk-our), with its default backend.  An item that did not end in
# OK counts when the built R has it and neither reference run does; a line
# of the example and test output counts when the built R departs from the
# reference where the two reference runs agree (compare-rout.py), so what
# varies between any two runs drops out by itself.  A difference in output
# raises no NOTE, so only the comparison shows it; since R itself changes
# between revisions, it decides only when both Rs are the same revision and
# is reported otherwise.  The items decide always: the installer is the
# older R as a rule, so items that drift brings appear in the reference.  Prints the revision of each R, the items per run
# and the lines that count, and exits 1 when anything that decides counts
# or a check did not finish.
refbin=$1 bin=$2; shift 2
export LC_ALL=C MAKEFLAGS=-j2 _R_CHECK_CRAN_INCOMING_=false \
    _R_CHECK_CRAN_INCOMING_REMOTE_=false _R_CHECK_FORCE_SUGGESTS_=false \
    _R_CHECK_SYSTEM_CLOCK_=false
for r in "$refbin" "$bin"; do
    echo "$r: $("$r/Rscript" -e 'cat(R.version.string)')"
done
svnrev() { "$1/Rscript" -e 'cat(R.version[["svn rev"]])'; }
home() { "$1/Rscript" -e 'cat(normalizePath(R.home(), "/"))'; }
refrev=$(svnrev "$refbin") ourrev=$(svnrev "$bin")
refhome=$(home "$refbin") ourhome=$(home "$bin")
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
# the Windows Store stub answers command -v and fails: try each
py=
for c in python python3 py; do "$c" -c '' 2> /dev/null && { py=$c; break; }; done
[ -n "$py" ] || { echo "no Python"; exit 1; }
# output differs also where R itself changed between two revisions, so
# only the same revision decides
outstatus=0
echo "output lines in which the built R departs from a stable reference:"
for p in "$@"; do
    for f in $p-Ex.Rout $(for r in ref1 our; do (cd chk-$r/$p.Rcheck 2> /dev/null && ls tests/*.Rout 2> /dev/null); done | sort -u); do
        a=chk-ref1/$p.Rcheck/$f b=chk-ref2/$p.Rcheck/$f c=chk-our/$p.Rcheck/$f
        if [ -f $a ] && [ -f $b ] && [ -f $c ]; then
            "$py" "$(dirname "$0")/compare-rout.py" "$refhome" "$ourhome" $a $b $c > cmp.txt || { echo "  $p $f: compare-rout.py failed"; status=1; continue; }
            n=$(tail -1 cmp.txt | tr -d '\r')
            echo "  $p $f: $n"
            [ "$n" = 0 ] || { outstatus=1; sed '$d' cmp.txt | head -40 | sed 's/^/    /'; }
        else
            echo "  $p $f: not in every run"
            status=1
        fi
    done
done
if [ "$refrev" = "$ourrev" ]; then
    [ $outstatus = 0 ] || status=1
else
    echo "the reference is r$refrev and the built R r$ourrev: the output is reported, not decided"
fi
exit $status

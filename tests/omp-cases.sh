#!/bin/bash
# The thread-count cases behind patches/openblas/ against one libopenblas:
#   omp-cases.sh LIBOPENBLAS
# builds omp-team.c and omp-nested.c beside it with $CC -fopenmp (gcc by
# default; clang on aarch64), against dlfcn-win32 from Rtools on Windows,
# and prints one line per case: the OpenMP environment, the count set, and
# ok with the count OpenBLAS reports after setting it, HANG when the run
# is still going after 8 s and again after 120 s (timeout's status 124,
# since the alarm in the programs is not available on Windows), SLOW when
# it finished only in the second run, or FAIL with the exit status or what
# came out; the time of dgemm follows ok.  Every omp-team case is one way for the OpenMP team to be
# smaller than the count; see the table in the notes.  The omp-nested case
# calls dgemm from a parallel region and checks the results; what it shows
# depends on whether the caller shares OpenBLAS's OpenMP runtime (see
# omp-nested.c).  Each omp-team case carries the count
# OpenBLAS must report: the count set, 1 under OMP_THREAD_LIMIT=1, and the
# compiled-in cap of 64 above it.  Prints the tally and the cases that are
# not ok last, and exits 1 unless every case is ok.
lib=$1
dir=$(dirname "$0")
cc=${CC:-gcc}
set -e
$cc -O2 -fopenmp -o omp-team "$dir/omp-team.c" -ldl
$cc -O2 -fopenmp -o omp-nested "$dir/omp-nested.c" -ldl -lm
set +e
echo "$($cc --version | head -1); $(nproc) processors"
n=0
ok=0
bad=
case_line() {   # case_line LABEL REQ RESULT
    n=$((n + 1))
    line=$(printf '%-36s set %-3s %s' "$1" "$2" "$3")
    echo "$line"
    case "$3" in ok*) ok=$((ok + 1)) ;; *) bad="$bad$line"$'\n' ;; esac
}
run() {   # run COMMAND...; sets out and r to the output and the verdict so far
    out=$(timeout 8 "$@" 2>&1)
    status=$?
    if [ $status = 124 ]; then
        # a hang or only slow: run again with 120 s, and keep the case not
        # ok either way
        start=$SECONDS
        out=$(timeout 120 "$@" 2>&1)
        status=$?
        if [ $status = 124 ]; then r="HANG, also with 120 s"
        else r="SLOW, over 8 s, then $((SECONDS - start)) s with status $status: $out"; fi
    elif [ $status != 0 ]; then r="FAIL, exit status $status: $out"
    else r=; fi
}
team() {   # team "ENV=..." REQ...; must report REQ, or 1 under a limit of 1, at most 64
    local env=$1; shift
    for req in "$@"; do
        case "$env" in *OMP_THREAD_LIMIT=1*) exp=1 ;; *) exp=$req ;; esac
        [ "$exp" -gt 64 ] && exp=64
        run env $env ./omp-team "$lib" "$req"
        if [ -z "$r" ]; then
            got=$(echo "$out" | sed -n 's/^ok [0-9.]*s (reported [0-9]*, set [0-9]* -> \([0-9]*\),.*/\1/p')
            if [ "$got" = "$exp" ]; then r="ok, reports $got, dgemm $(echo "$out" | sed -n 's/^ok \([0-9.]*s\).*/\1/p')"
            else r="FAIL, reports ${got:-nothing}, expected $exp: $out"; fi
        fi
        case_line "${env:-default}" "$req" "$r"
    done
}
team "" 2 4 8 64 100
team "OMP_NUM_THREADS=1" 2 4 8
team "OMP_THREAD_LIMIT=1" 2 4
team "OMP_NUM_THREADS=1 OMP_THREAD_LIMIT=1" 2
team "OMP_DYNAMIC=true" 2 4 8
team "OMP_NUM_THREADS=1 OMP_DYNAMIC=true" 2 4
team "OMP_THREAD_LIMIT=1 OMP_DYNAMIC=true" 2
for req in 2 0; do
    run ./omp-nested "$lib" "$req"
    if [ -z "$r" ]; then
        case "$out" in
            "ok (set $req, reports "*) r=ok ;;
            *) r="FAIL: $out" ;;
        esac
    fi
    case_line "inside a parallel region of 2" "$req" "$r"
done
echo "cases: $ok of $n ok"
[ -z "$bad" ] || printf 'not ok:\n%s' "$bad"
[ "$ok" -eq "$n" ]

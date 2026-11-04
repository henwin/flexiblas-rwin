#!/bin/bash
# The thread-count cases behind patches/openblas/ against one libopenblas:
#   omp-cases.sh LIBOPENBLAS
# builds omp-team.c and omp-nested.c beside it (gcc -fopenmp, dlfcn-win32
# from Rtools on Windows) and prints one line per case: the OpenMP
# environment, the count set, and ok with the count OpenBLAS ran with, or
# HANG (timeout 8 s, since the alarm in the programs is not available on
# Windows), or what came out when it is not what the patches promise.
# Every case is one way for the OpenMP team to be smaller than the count;
# see the table in the notes.  Each case carries the count it must run
# with: the count set, 1 under OMP_THREAD_LIMIT=1, and the compiled-in cap
# of 64 above it.  Exits 1 unless every case is ok, and prints the tally
# last.
lib=$1
dir=$(dirname "$0")
set -e
gcc -O2 -fopenmp -o omp-team "$dir/omp-team.c" -ldl
gcc -O2 -fopenmp -o omp-nested "$dir/omp-nested.c" -ldl
set +e
echo "$(gcc --version | head -1); $(nproc) processors"
ok=0 n=0
case_line() {   # case_line LABEL REQ EXPECTED OUTPUT
    n=$((n + 1))
    case "$4" in ok*) ok=$((ok + 1)) ;; esac
    printf '%-36s set %-3s %s\n' "$1" "$2" "$4"
}
team() {   # team "ENV=..." REQ...; runs REQ, or 1 under a limit of 1, or 64
    local env=$1; shift
    for req in "$@"; do
        case "$env" in *OMP_THREAD_LIMIT=1*) exp=1 ;; *) exp=$req ;; esac
        [ "$exp" -gt 64 ] && exp=64
        out=$(env $env timeout 8 ./omp-team "$lib" "$req" 2>&1)
        ran=$(echo "$out" | sed -n 's/^ok [0-9.]*s (reported [0-9]*, set [0-9]* -> \([0-9]*\), after \([0-9]*\);.*/\1/p')
        if [ -z "$out" ]; then r=HANG
        elif [ "$ran" = "$exp" ]; then r="ok, ran $ran"
        else r="FAIL, expected $exp: $out"; fi
        case_line "${env:-default}" "$req" "$exp" "$r"
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
    out=$(timeout 8 ./omp-nested "$lib" "$req" 2>&1)
    case "$out" in
        "") r=HANG ;;
        "ok (set $req, reports "*) r="ok" ;;
        *) r="FAIL: $out" ;;
    esac
    case_line "inside a parallel region of 2" "$req" ok "$r"
done
echo "cases: $ok of $n ok"
[ "$ok" -eq "$n" ]

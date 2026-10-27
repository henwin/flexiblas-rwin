#!/bin/bash
# The thread-count cases behind patches/openblas/ against one libopenblas:
#   omp-cases.sh LIBOPENBLAS
# builds omp-team.c and omp-nested.c beside it (gcc -fopenmp, dlfcn-win32
# from Rtools on Windows) and prints one line per case: the OpenMP
# environment, the count set, and ok with the count OpenBLAS ran with, or
# HANG (timeout 8 s, since the alarm in the programs is not available on
# Windows).  Every case is one way for the OpenMP team to be smaller than
# the count; see the table in the notes.
lib=$1
dir=$(dirname "$0")
gcc -O2 -fopenmp -o omp-team "$dir/omp-team.c" -ldl
gcc -O2 -fopenmp -o omp-nested "$dir/omp-nested.c" -ldl
echo "$(gcc --version | head -1); $(nproc) processors"
team() {   # team "ENV=..." REQ...
    local env=$1; shift
    for req in "$@"; do
        r=$(env $env timeout 8 ./omp-team "$lib" "$req" 2>&1 | sed -e 's/^ok [0-9.]*s (reported [0-9]*, set [0-9]* -> \([0-9]*\), after \([0-9]*\);.*/ok, ran \1, reports \2/')
        printf '%-36s set %-3s %s\n' "${env:-default}" "$req" "${r:-HANG}"
    done
}
team "" 2 4
team "OMP_NUM_THREADS=1" 2 4
team "OMP_THREAD_LIMIT=1" 2 4
team "OMP_NUM_THREADS=1 OMP_THREAD_LIMIT=1" 2
team "OMP_DYNAMIC=true" 2 4
team "OMP_NUM_THREADS=1 OMP_DYNAMIC=true" 2 4
team "OMP_THREAD_LIMIT=1 OMP_DYNAMIC=true" 2
for req in 2 0; do
    r=$(timeout 8 ./omp-nested "$lib" "$req" 2>&1)
    printf '%-36s set %-3s %s\n' "inside a parallel region of 2" "$req" "${r:-HANG}"
done

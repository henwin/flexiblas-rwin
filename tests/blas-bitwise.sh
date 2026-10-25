#!/usr/bin/env bash
# Build R's BLAS (src/extra/blas) as a DLL with R's flags and with candidate
# flag sets, and compare each, routine by routine and bit for bit, with the
# one built with R's flags (tests/blas-bitwise.c). Also compares that one
# with the Rblas.dll of the R in RHOME, if given, to check that it is R's.
#   bash tests/blas-bitwise.sh BLAS_SRC [RHOME]
# BLAS_SRC holds blas.f, blas2.f90, cmplxblas.f, cmplxblas2.f90 and
# Rblas.def; Rtools' gcc and gfortran must be on PATH.
set -euo pipefail
src=$1
rhome=${2:-}
here=$(cd "$(dirname "$0")" && pwd)
EOPTS="-mfpmath=sse -msse2 -mstackrealign"
SETS=(
  "R|-O2 $EOPTS"
  "O3|-O3 $EOPTS"
  "x86-64-v2|-O2 $EOPTS -march=x86-64-v2"
  "x86-64-v2-O3|-O3 $EOPTS -march=x86-64-v2"
  "x86-64-v3|-O2 $EOPTS -march=x86-64-v3"
  "x86-64-v3-nofma|-O2 $EOPTS -march=x86-64-v3 -ffp-contract=off"
  "x86-64-v3-O3-nofma|-O3 $EOPTS -march=x86-64-v3 -ffp-contract=off"
)
gcc -O2 -o blas-xerbla.o -c "$here/blas-xerbla.c"
gcc -O2 -std=gnu11 -o blas-bitwise.exe "$here/blas-bitwise.c"
for s in "${SETS[@]}"; do
  IFS='|' read -r name flags <<< "$s"
  mkdir -p "obj-$name"
  for f in blas.f blas2.f90 cmplxblas.f cmplxblas2.f90; do
    gfortran $flags -c "$src/$f" -o "obj-$name/${f%.*}.o" -J "obj-$name"
  done
  gfortran -shared -s -o "blas-$name.dll" obj-$name/*.o blas-xerbla.o "$src/Rblas.def"
done
# The build with R's flags must reproduce R's Rblas.dll, or the comparisons
# below say nothing; differences under other flags are the results, so only
# errors (exit status 2 and above) fail those.
status=0
if [ -n "$rhome" ]; then
  echo "== blas-R.dll against $rhome/bin/x64/Rblas.dll"
  rc=0; ./blas-bitwise.exe "$(cygpath -w "$rhome/bin/x64/Rblas.dll")" blas-R.dll > cmp-cran.txt || rc=$?
  tail -1 cmp-cran.txt
  [ $rc -eq 0 ] || { echo "the build with R's flags is not R's Rblas.dll (exit status $rc)"; status=1; }
fi
for s in "${SETS[@]:1}"; do
  name=${s%%|*}
  echo "== $name: ${s#*|}"
  rc=0; ./blas-bitwise.exe blas-R.dll "blas-$name.dll" > "cmp-$name.txt" || rc=$?
  grep -v ' 0 differ$' "cmp-$name.txt" || true
  [ $rc -le 1 ] || { echo "error (exit status $rc)"; status=1; }
done
exit $status

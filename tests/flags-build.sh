#!/usr/bin/env bash
# Build Rblas.dll and Rlapack.dll from R's sources as R's Windows build does
# (src/extra/blas, src/modules/lapack), with R's flags and with other
# optimisation levels and -march=native, into blas-NAME/ and lapack-NAME/.
#   bash tests/flags-build.sh SRC RHOME
# SRC holds the files of src/extra/blas and src/modules/lapack; RHOME is the
# R whose R.dll and Rblas.dll they link against. Rtools' gcc and gfortran
# must be on PATH.
set -euo pipefail
src=$1
rhome=$2
EOPTS="-mfpmath=sse -msse2 -mstackrealign"
BLAS_SETS=(
  "R|-O2 $EOPTS"
  "O3|-O3 $EOPTS"
  "native-O2|-O2 $EOPTS -march=native"
  "native-O3|-O3 $EOPTS -march=native"
)
LAPACK_SETS=(
  "R|-O3 $EOPTS"
  "O2|-O2 $EOPTS"
  "native-O2|-O2 $EOPTS -march=native"
  "native-O3|-O3 $EOPTS -march=native"
)
bin=$rhome/bin/x64

for s in "${BLAS_SETS[@]}"; do
  IFS='|' read -r name flags <<< "$s"
  d=blas-$name; mkdir -p "$d"
  for f in blas.f blas2.f90 cmplxblas.f cmplxblas2.f90; do
    gfortran $flags -c "$src/$f" -o "$d/${f%.*}.o" -J "$d"
  done
  gfortran -shared -s -o "$d/Rblas.dll" "$d"/*.o "$src/Rblas.def" -L"$bin" -lR
done

for s in "${LAPACK_SETS[@]}"; do
  IFS='|' read -r name flags <<< "$s"
  d=lapack-$name; mkdir -p "$d"
  # order as in Makefile.win: the modules first; dlamch.f with -ffloat-store
  for f in la_constants.f90 la_xisnan.f90 dlartg.f90 dlassq.f90 zlartg.f90 zlassq.f90 dlapack.f cmplx.f; do
    gfortran $flags -c "$src/$f" -o "$d/${f%.*}.o" -J "$d" -I "$d"
  done
  gfortran $flags -ffloat-store -c "$src/dlamch.f" -o "$d/dlamch.o"
  { echo EXPORTS; nm "$d"/*.o | sed -n 's/^.* [BCDRT] / /p' | sort | uniq; } > "$d/Rlapack.def"
  gfortran -shared -s -o "$d/Rlapack.dll" "$d"/*.o "$d/Rlapack.def" -L"$bin" -lR -lRblas
done
ls -la blas-*/Rblas.dll lapack-*/Rlapack.dll

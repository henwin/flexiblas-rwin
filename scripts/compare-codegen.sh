#!/usr/bin/env bash
# Compile R's BLAS and LAPACK sources with R's flags and with candidate flag
# sets, and list, per candidate, the routines whose machine code differs
# from R's. Where the code is identical the results are identical; only the
# routines listed need a numerical comparison.
#   bash scripts/compare-codegen.sh R_SRC [OUT]
# R_SRC is an R source tree (src/extra/blas, src/modules/lapack); the MXE
# cross compiler of Rtools45 must be on PATH (as in docker/Dockerfile).
set -euo pipefail
R_SRC=$1
OUT=${2:-codegen}
TRIPLET=${TRIPLET:-x86_64-w64-mingw32.static.posix}
FC="$TRIPLET-gfortran"
OBJDUMP="$TRIPLET-objdump"
EOPTS="-mfpmath=sse -msse2 -mstackrealign"
BLAS="blas.f blas2.f90 cmplxblas.f cmplxblas2.f90"
LAPACK="la_constants.f90 la_xisnan.f90 dlartg.f90 dlassq.f90 zlartg.f90 zlassq.f90 dlapack.f cmplx.f"

# name|BLAS flags|LAPACK flags; the first is R's (src/gnuwin32/Makefile,
# src/modules/lapack/Makefile.win; dlamch.f is compiled apart and left out)
SETS=(
  "R|-O2 $EOPTS|-O3 $EOPTS"
  "blas-O3|-O3 $EOPTS|-O3 $EOPTS"
  "x86-64-v2|-O2 $EOPTS -march=x86-64-v2|-O3 $EOPTS -march=x86-64-v2"
  "x86-64-v3|-O2 $EOPTS -march=x86-64-v3|-O3 $EOPTS -march=x86-64-v3"
  "x86-64-v3-nofma|-O2 $EOPTS -march=x86-64-v3 -ffp-contract=off|-O3 $EOPTS -march=x86-64-v3 -ffp-contract=off"
)

mkdir -p "$OUT"
for s in "${SETS[@]}"; do
  IFS='|' read -r name bflags lflags <<< "$s"
  d="$OUT/$name"; rm -rf "$d"; mkdir -p "$d"
  for f in $BLAS; do
    $FC $bflags -ffunction-sections -c "$R_SRC/src/extra/blas/$f" -o "$d/${f%.*}.o" -J "$d"
  done
  for f in $LAPACK; do
    $FC $lflags -ffunction-sections -c "$R_SRC/src/modules/lapack/$f" -o "$d/${f%.*}.o" -J "$d" -I "$d"
  done
  # one hash per function, from the disassembly without addresses, raw bytes
  # or relocation offsets, so that only the instructions count
  for o in "$d"/*.o; do
    $OBJDUMP -d --no-addresses --no-show-raw-insn "$o"
  done | awk '
    / file format / || /^Disassembly of section/ { next }
    /^<.*>:$/ { if (name) print name, body; name = substr($0, 2, length($0) - 3); body = ""; next }
    name && NF { gsub(/[ \t]+/, " "); gsub(/0x[0-9a-f]+/, "X"); gsub(/<[^>]*>/, "<>"); body = body ";" $0 }
    END { if (name) print name, body }' |
    while read -r fn rest; do printf '%s %s\n' "$fn" "$(printf '%s' "$rest" | md5sum | cut -c1-12)"; done |
    sort > "$d/hashes.txt"
  echo "$name: $(wc -l < "$d/hashes.txt") functions"
done

echo
echo "Functions whose code differs from R's flags:"
for s in "${SETS[@]:1}"; do
  name=${s%%|*}
  diff=$(join "$OUT/R/hashes.txt" "$OUT/$name/hashes.txt" | awk '$2 != $3 { print $1 }')
  n=$(printf '%s' "$diff" | grep -c . || true)
  printf '%-16s %4d of %d differ\n' "$name" "$n" "$(wc -l < "$OUT/R/hashes.txt")"
  printf '%s\n' "$diff" > "$OUT/$name/differs.txt"
done

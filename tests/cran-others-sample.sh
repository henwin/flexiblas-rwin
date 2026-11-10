#!/bin/bash
# A sample of the CRAN packages that do not call the BLAS or LAPACK
# themselves: of the packages with a Windows binary for R VERSION, those
# that tests/cran-blas-users.sh does not list, less the recommended ones,
# the N first when ordered by the SHA-256 of "SEED:package", so that the
# same SEED and the same CRAN give the same sample on any machine.
#   tests/cran-others-sample.sh 4.6 1000 1 > packages.txt
set -eo pipefail
export LC_ALL=C
ver=$1; n=$2; seed=$3
[[ $n =~ ^[0-9]+$ && -n $seed ]] || { echo "usage: cran-others-sample.sh VERSION N SEED" >&2; exit 2; }
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
"$(dirname "$0")/cran-blas-users.sh" "$ver" > "$w/blas"
curl -sSf "https://cloud.r-project.org/bin/windows/contrib/$ver/PACKAGES" | tr -d '\r' |
    awk '/^Package:/ {p = $2} /^Priority: *recommended/ {r[p] = 1} /^File:/ {f[p] = 1}
         END {for (p in f) if (!(p in r)) print p}' | sort -u > "$w/all"
comm -23 "$w/all" "$w/blas" > "$w/others"
echo "$(wc -l < "$w/all") Windows binaries not recommended, $(wc -l < "$w/blas") call the BLAS or LAPACK, $(wc -l < "$w/others") do not" >&2
# awk rather than head, which would end sort with SIGPIPE under pipefail
SEED=$seed perl -MDigest::SHA=sha256_hex -nle 'print substr(sha256_hex("$ENV{SEED}:$_"), 0, 16), " $_"' "$w/others" |
    sort | awk -v n="$n" 'NR <= n {print $2}' | sort

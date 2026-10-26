#!/bin/bash
# The CRAN packages that call the BLAS or LAPACK themselves: those whose
# Windows binary has a DLL importing from Rblas.dll or Rlapack.dll. Only
# packages with compiled code are downloaded.
#   tests/cran-blas-users.sh 4.6 > packages.txt
set -eo pipefail
export LC_ALL=C
ver=$1
repo=https://cloud.r-project.org
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
curl -sSf "$repo/src/contrib/PACKAGES" | tr -d '\r' |
    awk '/^Package:/ {p = $2} /^NeedsCompilation: *yes/ {print p}' | sort -u > "$w/compiled"
curl -sSf "$repo/bin/windows/contrib/$ver/PACKAGES" | tr -d '\r' |
    awk '/^Package:/ {p = $2} /^File:/ {print p, $2}' | sort -k1,1 |
    join - "$w/compiled" > "$w/zips"
echo "$(wc -l < "$w/zips") Windows binaries with compiled code" >&2

one() {
    d=$(mktemp -d)
    if curl -sSf -o "$d/z" "$1/$3"; then
        unzip -qq -o "$d/z" '*/libs/*' -d "$d" 2>/dev/null || true
        for f in $(find "$d" -name '*.dll'); do
            if [ "$(objdump -p "$f" | grep -ciE 'DLL Name: R(blas|lapack)\.dll')" -gt 0 ]; then
                echo "$2"; break
            fi
        done
    else
        echo "not downloaded: $3" >&2
    fi
    rm -rf "$d"
}
export -f one
xargs -P 32 -n 2 bash -c 'one "$0" "$1" "$2"' "$repo/bin/windows/contrib/$ver" < "$w/zips" | sort

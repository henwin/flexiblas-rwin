#!/usr/bin/env bash
# Build everything in the container defined by docker/Dockerfile, with this
# repository mounted at /work. Results: openblas-dist/ and dist/.
# OpenBLAS (about two hours on four cores) is built only when
# openblas-dist/ is missing or --openblas is given.
set -euo pipefail
cd "$(dirname "$0")/.."

image=flexiblas-rwin-build
docker build -t "$image" -f docker/Dockerfile .

steps='bash scripts/build.sh'
if [ "${1:-}" = --openblas ] || ! ls openblas-dist/libopenblas_*.dll >/dev/null 2>&1; then
    steps="bash scripts/build-openblas.sh && $steps"
fi
docker run --rm -v "$PWD":/work -w /work "$image" bash -c "$steps"

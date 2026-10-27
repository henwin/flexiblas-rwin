#!/usr/bin/env bash
# Build everything in the image from docker/Dockerfile (R's MXE tree with the
# Rtools45 toolchain), with this repository mounted at /work:
# scripts/build-mxe.sh rebuilds OpenBLAS with the Rtools patches (cached in
# mxe-out/), and scripts/build-bundle.sh builds the FlexiBLAS bundle into
# dist/FlexiBLAS and dist/FlexiBLAS.zip; with the argument aarch64, for
# that target (the image then also holds the aarch64 toolchain).
set -euo pipefail
cd "$(dirname "$0")/.."
target=${1:-x86_64}

image=flexiblas-rwin-mxe
docker build -t "$image" -f docker/Dockerfile \
    --build-arg WITH_AARCH64=$([ "$target" = aarch64 ] && echo yes || echo no) .
docker run --rm -v "$PWD":/work -w /work "$image" bash -c \
    "bash scripts/build-mxe.sh $target && bash scripts/build-bundle.sh $target"

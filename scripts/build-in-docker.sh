#!/usr/bin/env bash
# Build everything in the image from docker/Dockerfile (R's MXE tree with the
# Rtools45 toolchain), with this repository mounted at /work:
# scripts/build-mxe.sh rebuilds OpenBLAS with the Rtools patches (cached in
# mxe-out/), and scripts/build-bundle.sh builds the FlexiBLAS bundle into
# dist/FlexiBLAS and dist/FlexiBLAS.zip.
set -euo pipefail
cd "$(dirname "$0")/.."

image=flexiblas-rwin-mxe
docker build -t "$image" -f docker/Dockerfile .
docker run --rm -v "$PWD":/work -w /work "$image" bash -c \
    'bash scripts/build-mxe.sh && bash scripts/build-bundle.sh'

#!/usr/bin/env bash
# Build everything in the image from docker/Dockerfile (R's MXE tree with the
# Rtools45 toolchain), with this repository mounted at /work:
# scripts/build-mxe.sh builds OpenBLAS and FlexiBLAS with MXE into dist/,
# scripts/forwarders.sh adds the forwarding Rblas.dll/Rlapack.dll and the
# test shim. Pass --forwarders-only when dist/ already holds the MXE build.
set -euo pipefail
cd "$(dirname "$0")/.."

image=flexiblas-rwin-mxe
docker build -t "$image" -f docker/Dockerfile .

steps='bash scripts/forwarders.sh'
[ "${1:-}" = --forwarders-only ] || steps="bash scripts/build-mxe.sh && $steps"
docker run --rm -v "$PWD":/work "$image" bash -c "$steps"

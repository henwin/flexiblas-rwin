# Linux build environment for the Windows FlexiBLAS setup: Ubuntu with the
# Rtools45 cross toolchain from CRAN assembled as an MXE tree at
# /usr/lib/mxe/usr. Build with scripts/build-in-docker.sh.
FROM ubuntu:24.04

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates curl git zstd xz-utils unzip innoextract \
        cmake make gcc g++ perl python3 \
 && rm -rf /var/lib/apt/lists/*

ARG RTOOLS_BUILD=6768
COPY scripts/setup-toolchain.sh /tmp/setup-toolchain.sh
RUN RTOOLS_BUILD=$RTOOLS_BUILD TOP=/opt/rtools45 bash /tmp/setup-toolchain.sh \
 && rm /opt/rtools45/*.tar.zst

WORKDIR /work

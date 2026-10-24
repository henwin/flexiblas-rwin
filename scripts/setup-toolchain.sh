#!/usr/bin/env bash
# Assemble the Rtools45 cross toolchain from CRAN's tarballs as an MXE tree
# at /usr/lib/mxe/usr (the prefix hard-coded in the MXE wrappers).
set -euo pipefail

RTOOLS_BUILD=${RTOOLS_BUILD:-6768}
CRAN=https://cran.r-project.org/bin/windows/Rtools/rtools45/files
TOP=${TOP:-$PWD/toolchain}
TARGET=x86_64-w64-mingw32.static.posix

mkdir -p "$TOP/cross" "$TOP/full"
cd "$TOP"
for kind in cross full; do
    f=rtools45-toolchain-libs-$kind-$RTOOLS_BUILD.tar.zst
    [ -f "$f" ] || curl -sSfLO "$CRAN/$f"
    tar --zstd -xf "$f" -C "$kind"
done

# The cross tarball has the compiler but no target headers or libraries;
# those come from the full tarball. Binutils must be found under the target
# directory, otherwise GCC falls back to the host assembler.
T=cross/$TARGET
mkdir -p "$T/bin"
for d in include lib share; do
    ln -sfn "../../full/$TARGET/$d" "$T/$d"
done
for t in as ld ar nm ranlib objdump dlltool strip; do
    ln -sfn "../../bin/$TARGET-$t" "$T/bin/$t"
done

# mxe-conf.d/ccache.cmake points the compilers at ccache wrappers that the
# tarball does not contain; provide plain wrappers instead.
for c in gcc g++ gfortran; do
    printf '#!/bin/sh\nexec /usr/lib/mxe/usr/bin/%s-%s "$@"\n' "$TARGET" "$c" \
        > "cross/x86_64-pc-linux-gnu/bin/$TARGET-$c"
    chmod +x "cross/x86_64-pc-linux-gnu/bin/$TARGET-$c"
done

SUDO=; [ "$(id -u)" = 0 ] || SUDO=sudo
$SUDO mkdir -p /usr/lib/mxe
$SUDO ln -sfn "$TOP/cross" /usr/lib/mxe/usr
/usr/lib/mxe/usr/bin/$TARGET-gcc --version | head -1

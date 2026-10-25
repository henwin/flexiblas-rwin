#!/usr/bin/env bash
# Generate the forwarding Rblas.dll and Rlapack.dll in dist/forwarders, for
# the FlexiBLAS bundle that scripts/build-bundle.sh put in dist/FlexiBLAS.
#
# The forwarders export exactly what R's own DLLs export, forwarded to
# libflexiblas.dll, so that R.dll and every module reach one FlexiBLAS
# instance. Rlapack symbols that FlexiBLAS lacks are forwarded to R's
# original Rlapack.dll, which the installation keeps as Rlapack_ref.dll.
set -euo pipefail
R_VERSION=${R_VERSION:-4.6.1}
TARGET=x86_64-w64-mingw32.static.posix
export PATH=/usr/lib/mxe/usr/bin:$PATH
WORK=${WORK:-/work}
DIST=$WORK/dist
tmp=$(mktemp -d)
cd "$tmp"

exports() {
    $TARGET-objdump -p "$1" |
        awk '/\[Ordinal\/Name Pointer\] Table/{f=1;next} f&&NF==0{f=0} f{print $NF}' |
        grep -v '^Name$' | sort
}

exe=$DIST/R-$R_VERSION-win.exe
[ -f "$exe" ] || curl -sSfL -o "$exe" "https://cran.r-project.org/bin/windows/base/R-$R_VERSION-win.exe"
innoextract -q -d rwin -I app/bin/x64 "$exe"
exports "$DIST/FlexiBLAS/bin/x64/libflexiblas.dll" > flexiblas.exports
mkdir -p "$DIST/forwarders"
echo 'void forwarder(void) {}' > fwd.c
for lib in Rblas Rlapack; do
    exports "rwin/app/bin/x64/$lib.dll" > "$lib.exports"
    missing=$(comm -23 "$lib.exports" flexiblas.exports)
    if [ "$lib" = Rblas ] && [ -n "$missing" ]; then
        echo "libflexiblas.dll lacks Rblas exports: $missing" >&2
        exit 1
    fi
    [ -z "$missing" ] || echo "$lib: forwarded to Rlapack_ref.dll:" $missing
    {
        echo "LIBRARY $lib.dll"
        echo "EXPORTS"
        comm -12 "$lib.exports" flexiblas.exports | sed 's/.*/& = libflexiblas.&/'
        comm -23 "$lib.exports" flexiblas.exports | sed 's/.*/& = Rlapack_ref.&/'
    } > "$lib.def"
    $TARGET-gcc -shared -nostdlib -Wl,-e,0 -o "$DIST/forwarders/$lib.dll" fwd.c "$lib.def"
done

ls -la "$DIST/forwarders"

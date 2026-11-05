#!/usr/bin/env bash
# Inside the image from docker/Dockerfile, after scripts/build-mxe.sh: build
# the FlexiBLAS bundle with patches/r-dev-web/flexiblas_bundle/build_ucrt.sh,
# as R-core builds the Tcl/Tk bundle, for the target given (x86_64 by
# default, or aarch64), and unpack it into dist/FlexiBLAS (dist/FlexiBLAS-aarch64).
set -euo pipefail
WORK=${WORK:-/work}
target=${1:-x86_64}
case $target in
    x86_64)  mxe=/opt/mxe; name=FlexiBLAS ;;
    aarch64) mxe=/opt/mxe-aarch64; name=FlexiBLAS-aarch64 ;;
    *) echo "unknown target $target" >&2; exit 2 ;;
esac
export PATH=$mxe/usr/bin:$PATH
b=$(mktemp -d)
cp "$WORK"/patches/r-dev-web/flexiblas_bundle/build_ucrt.sh "$b"
# flexiblas.diff, which build_ucrt.sh applies as tcl_bundle applies tcl.diff
cat "$WORK"/patches/flexiblas/*.patch > "$b/flexiblas.diff"
# the OpenBLAS patches as MXE has them after build-mxe.sh, R-core's and ours,
# for the pthreads build of the bundle
cp "$mxe"/src/openblas-*.patch "$b"
cd "$b"
# the pthreads OpenBLAS the bundle builds, kept in bundle-out by the hash of
# what it is built from: the bundle script, the OpenBLAS patches copied
# above and the version of the toolchain's OpenBLAS
h=$( { cat build_ucrt.sh openblas-*.patch; $target-w64-mingw32.static.posix-pkg-config --modversion openblas; } | sha256sum | cut -c1-12)
cache=$WORK/bundle-out/libopenblas-pthreads-$target-$h.a
[ ! -f "$cache" ] || cp "$cache" libopenblas-pthreads-$target.a
# CMake takes CMAKE_EXPORT_COMPILE_COMMANDS from the environment, so the
# flags of the reference BLAS and LAPACK can be shown without changing the
# bundle script.
status=0
CMAKE_EXPORT_COMPILE_COMMANDS=ON bash -x ./build_ucrt.sh $target 2>&1 | tee build_ucrt.out | tail -40 || status=$?
# the whole output of the bundle build, for the workflow's report, and the
# pthreads OpenBLAS for the cache, whether or not the bundle was finished
mkdir -p "$WORK/dist"; cp build_ucrt.out "$WORK/dist/build_ucrt-$target.out"
if [ -f libopenblas-pthreads-$target.a ] && [ ! -f "$cache" ]; then
    mkdir -p "$(dirname "$cache")"; cp libopenblas-pthreads-$target.a "$cache"
fi
[ "$status" = 0 ] || exit "$status"
cc=$(find . -name compile_commands.json | head -1)
if [ -n "$cc" ]; then
    for f in dgemm dpotrf; do
        grep -o "\"command\": \"[^\"]*/$f\\.f[^\"]*\"" "$cc" | head -1 || true
    done
else
    echo "no compile_commands.json (CMake older than 3.17?)"
fi
# what the DLLs import, and no compiler runtime in an export table: it is
# linked in statically and must stay private, or a program linking two of
# the DLLs gets duplicate definitions (llvm-objdump is off PATH in the
# LLVM toolchain; GNU and LLVM objdump list exports differently)
objdump=$(ls "$mxe"/usr/x86_64-pc-linux-gnu/bin/llvm-objdump 2>/dev/null || echo "$mxe/usr/bin/$target-w64-mingw32.static.posix-objdump")
for d in $(find FlexiBLAS -name '*.dll'); do
    echo "$d imports: $("$objdump" -p "$d" | awk '/DLL Name:/ {printf "%s ", $3}')"
    "$objdump" -p "$d" | awk '/\[Ordinal\/Name Pointer\] Table|^Export Table/ {e = 1; next} e && /^$/ {e = 0}
        e && (/^ +[0-9]+ +0x/ || /^[ \t]*\[ *[0-9]+\]/) {print $NF}' > exports.txt
    [ -s exports.txt ] || { echo "$d: no exports read" >&2; exit 1; }
    if grep -E '^(omp_|GOMP_|__stack_chk|_gfortran_|_Fortran)' exports.txt; then
        echo "$d exports the compiler runtime symbols above" >&2; exit 1
    fi
done
rm -rf "$WORK/dist/$name"
mkdir -p "$WORK/dist"
cp FlexiBLAS.zip "$WORK/dist/$name.zip"
cp -r FlexiBLAS "$WORK/dist/$name"

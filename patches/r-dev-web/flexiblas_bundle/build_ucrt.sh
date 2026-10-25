#! /bin/bash

set -e

# build_ucrt.sh [target]
#
# This builds the FlexiBLAS bundle using the MXE-based UCRT toolchain (see
# ../toolchain_libs), which must be on PATH.
#
# For the x86_64 target, it hence needs x86_64-w64-mingw32.static.posix-gcc,
# x86_64-w64-mingw32.static.posix-cmake, etc.  Only x86_64 is supported so
# far.
#
# FlexiBLAS loads its backends at run time and is therefore built as DLLs.
# The OPENBLAS backend contains the toolchain's static OpenBLAS.  The runtime
# libraries are linked in statically but not exported, since MinGW's
# export-all would otherwise export libssp's __stack_chk_fail and libgomp.
#
# The bundle has R's layout: the DLLs in bin/x64, the OPENBLAS backend in
# bin/x64/flexiblas, and the configuration in etc, which FlexiBLAS finds
# relative to its DLLs (../../etc, set by CMAKE_INSTALL_BINDIR).  R's
# Rblas.dll and Rlapack.dll forward to libflexiblas.dll.
#
# flexiblas.diff fixes finding the configuration and the vendor backends on
# Windows, and finding an autotools-built dlfcn-win32.
#
# clean via: rm -rf build FlexiBLAS *zip *gz
#
# See build_in_docker.sh for the currently needed dependencies on Ubuntu.

BHOME=`pwd`
BINST=$BHOME/FlexiBLAS

RTARGET="$1"
if [ "X$RTARGET" == X ] ; then
  RTARGET="x86_64"
fi

if [ ${RTARGET} != "x86_64" ] ; then
  echo "Unsupported target."
  exit 1
fi

TRIPLET=x86_64-w64-mingw32.static.posix
TLIB=`dirname \`which ${TRIPLET}-gcc\``/../${TRIPLET}/lib
EXCLUDE=libssp.a:libssp_nonshared.a:libgcc.a:libgcc_eh.a:libgfortran.a:libquadmath.a:libgomp.a:libwinpthread.a:libdl.a

echo "Building for target $RTARGET."

mkdir build

VER=3.5.0
if [ ! -r flexiblas-$VER.tar.gz ] ; then
  wget -O flexiblas-$VER.tar.gz https://github.com/mpimd-csc/flexiblas/archive/v$VER.tar.gz
fi
echo "175bd4ad7b44348c5dc0531c7a0169ad451cbc9a3d018dd17f01d4a0d0244680  flexiblas-$VER.tar.gz" | sha256sum -c

cd $BHOME/build
tar xfz $BHOME/flexiblas-$VER.tar.gz
cd flexiblas-$VER
patch -p1 < $BHOME/flexiblas.diff

# Compile as R compiles its own BLAS and LAPACK (src/gnuwin32/Makefile):
# Rblas.dll with FFLAGS='-O2 $(EOPTS)', the rest, LAPACK included, with
# '-O3 $(EOPTS)'.  The NETLIB backend, FlexiBLAS's copy of the reference
# BLAS, gets -O2 through a deferred call, since its target is defined in a
# subdirectory.
EOPTS="-mfpmath=sse -msse2 -mstackrealign"
cat > $BHOME/build/rflags.cmake <<'EOF'
cmake_language(DEFER CALL set_property TARGET flexiblas_netlib_objs APPEND PROPERTY
  COMPILE_OPTIONS "$<$<COMPILE_LANGUAGE:Fortran>:-O2>")
EOF

# ZDOTC_MKL_EXITCODE answers a try_run that cannot run when cross-compiling:
# OpenBLAS built with gfortran returns complex values the GNU way.
${TRIPLET}-cmake -S . -B build64 \
  -DCMAKE_BUILD_TYPE=Release \
  "-DCMAKE_C_FLAGS_RELEASE=-O3 -DNDEBUG $EOPTS" \
  "-DCMAKE_Fortran_FLAGS_RELEASE=-O3 $EOPTS" \
  -DCMAKE_PROJECT_FlexiBLAS_INCLUDE=$BHOME/build/rflags.cmake \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DCMAKE_INSTALL_PREFIX=$BINST \
  -DCMAKE_INSTALL_BINDIR=bin/x64 \
  -DBUILD_SHARED_LIBS=ON \
  -DINTEGER8=OFF \
  -DTESTS=OFF \
  -DEXAMPLES=OFF \
  -DLTO=OFF \
  -DBLAS_AUTO_DETECT=OFF \
  -DEXTRA=OPENBLAS \
  "-DOPENBLAS_LIBRARY=-Wl,--whole-archive;$TLIB/libopenblas.a;-Wl,--no-whole-archive;gfortran;quadmath;gomp;pthread" \
  -DOPENBLAS_LINKER_FLAGS=-fopenmp \
  -DZDOTC_MKL_EXITCODE=1 \
  "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--exclude-libs,$EXCLUDE" 2>&1 | tee configure64.out
make -C build64 -j 2>&1 | tee make64.out
make -C build64 install 2>&1 | tee install64.out
cp configure64.out make64.out install64.out $BHOME/build
# the flags the reference BLAS and LAPACK were compiled with
grep -o '"command": "[^"]*/dgemm\.f[^"]*"' build64/compile_commands.json | head -1 || true
grep -o '"command": "[^"]*/dpotrf\.f[^"]*"' build64/compile_commands.json | head -1 || true

# import libraries, pkg-config files, headers and documentation are not needed
cd $BINST
rm -f `find . -name "*.a"`
rm -rf bin/x64/pkgconfig include share
${TRIPLET}-strip `find . -name "*.dll"`

# The bundle is in FlexiBLAS
cd $BHOME
zip -r FlexiBLAS FlexiBLAS
cp FlexiBLAS.zip build

# Sanity check
find FlexiBLAS | md5sum
du FlexiBLAS -ksk
${TRIPLET}-objdump -p FlexiBLAS/bin/x64/libflexiblas.dll | grep 'DLL Name'

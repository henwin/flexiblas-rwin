#! /bin/bash

set -e

# build_ucrt.sh [target]
#
# This builds the FlexiBLAS bundle using the MXE-based UCRT toolchain (see
# ../toolchain_libs), which must be on PATH.
#
# For the x86_64 target, it hence needs x86_64-w64-mingw32.static.posix-gcc,
# x86_64-w64-mingw32.static.posix-cmake, etc.
#
# The target is x86_64 by default. It can also be specified as aarch64.
#
# FlexiBLAS loads its backends at run time and is therefore built as DLLs.
# The OPENBLAS backend contains the toolchain's static OpenBLAS, which uses
# OpenMP; the OPENBLAS-PTHREADS backend contains an OpenBLAS built here with
# pthreads instead (x86_64 only for now), from the same sources with the
# same settings as the toolchain's openblas.mk otherwise.  The runtime
# libraries are linked in statically but not exported, since MinGW's
# export-all would otherwise export libssp's __stack_chk_fail and libgomp.
#
# The bundle has R's layout: the DLLs in bin/x64 (bin on aarch64), the
# OPENBLAS backend in bin/x64/flexiblas, and the configuration in etc, which
# FlexiBLAS finds relative to its DLLs (../../etc, set by
# CMAKE_INSTALL_BINDIR).  R's Rblas.dll and Rlapack.dll forward to
# libflexiblas.dll.
#
# flexiblas.diff fixes finding the configuration and the vendor backends on
# Windows, and finding an autotools-built dlfcn-win32.
#
# clean via: rm -rf build FlexiBLAS *zip *gz *.a
#
# See build_in_docker.sh for the currently needed dependencies on Ubuntu.

BHOME=`pwd`
BINST=$BHOME/FlexiBLAS

RTARGET="$1"
if [ "X$RTARGET" == X ] ; then
  RTARGET="x86_64"
fi

if [ ${RTARGET} == "aarch64" ] ; then
  TRIPLET=aarch64-w64-mingw32.static.posix
  CC=clang
  # the MXE objdump wrapper runs llvm-objdump, which the toolchain keeps
  # with the other LLVM tools, off PATH
  USRDIR=`dirname \`which ${TRIPLET}-clang\``/..
  export PATH=`dirname \`find $USRDIR -name llvm-objdump | head -1\``:$PATH
  # R's bin directory and EOPTS on aarch64 (WIN= and USE_LLVM=1 in MkRules)
  BINDIR=bin
  EOPTS=
  # the Fortran and OpenMP runtimes of LLVM, as R's FLIBS and -fopenmp
  FLIBS="FortranRuntime;FortranDecimal;c++;omp;pthread"
  # lld has no --exclude-libs; it leaves the runtime libraries out of the
  # export table by itself
  LDEXCLUDE=
  PTHREADS=no
else
  TRIPLET=x86_64-w64-mingw32.static.posix
  CC=gcc
  BINDIR=bin/x64
  EOPTS="-mfpmath=sse -msse2 -mstackrealign"
  FLIBS="gfortran;quadmath;gomp;pthread"
  LDEXCLUDE=-Wl,--exclude-libs,libssp.a:libssp_nonshared.a:libgcc.a:libgcc_eh.a:libgfortran.a:libquadmath.a:libgomp.a:libwinpthread.a:libdl.a
  PTHREADS=yes
fi
TLIB=`dirname \`which ${TRIPLET}-${CC}\``/../${TRIPLET}/lib

echo "Building for target $RTARGET."

mkdir build

# OpenBLAS with pthreads for the OPENBLAS-PTHREADS backend: the toolchain's
# openblas.mk settings except USE_OPENMP, and NUM_THREADS fixed at 64 rather
# than the processor count of the build machine.  The build takes an hour or
# more, so a libopenblas-pthreads.a left from an earlier run is reused, like
# the source tarballs.
OBVER=0.3.34
if [ ${PTHREADS} == "yes" ] ; then
  if [ ! -r $BHOME/libopenblas-pthreads.a ] ; then
    if [ ! -r OpenBLAS-$OBVER.tar.gz ] ; then
      wget -O OpenBLAS-$OBVER.tar.gz https://github.com/OpenMathLib/OpenBLAS/releases/download/v$OBVER/OpenBLAS-$OBVER.tar.gz
    fi
    cd $BHOME/build
    tar xfz $BHOME/OpenBLAS-$OBVER.tar.gz
    cd OpenBLAS-$OBVER
    make -j CC=${TRIPLET}-gcc FC=${TRIPLET}-gfortran HOSTCC=gcc CROSS=1 CROSS_SUFFIX=${TRIPLET}- \
      BINARY=64 NO_SHARED=1 BUILD_RELAPACK=1 USE_THREAD=1 USE_OPENMP=0 NUM_THREADS=64 \
      TARGET=CORE2 DYNAMIC_ARCH=1 libs netlib 2>&1 | tee $BHOME/build/openblas-pthreads.out | tail -5
    cp libopenblas.a $BHOME/libopenblas-pthreads.a
    cd $BHOME
  fi
  EXTRA="OPENBLAS;OPENBLAS-PTHREADS"
  PTHOPTS=("-DOPENBLAS-PTHREADS_LIBRARY=-Wl,--whole-archive;$BHOME/libopenblas-pthreads.a;-Wl,--no-whole-archive;gfortran;quadmath;pthread" -DOPENBLAS-PTHREADS_LINKER_FLAGS=)
else
  EXTRA=OPENBLAS
  PTHOPTS=()
fi

VER=3.5.0
if [ ! -r flexiblas-$VER.tar.gz ] ; then
  wget -O flexiblas-$VER.tar.gz https://github.com/mpimd-csc/flexiblas/archive/v$VER.tar.gz
fi

cd $BHOME/build
tar xfz $BHOME/flexiblas-$VER.tar.gz
cd flexiblas-$VER
patch -p1 < $BHOME/flexiblas.diff

# Compile as R compiles its own BLAS and LAPACK (src/gnuwin32/Makefile and
# src/modules/lapack/Makefile.win): Rblas.dll with FFLAGS='-O2 $(EOPTS)',
# Rlapack.dll with '-O3 $(EOPTS)' and dlamch.f also with -ffloat-store.
# FlexiBLAS's reference BLAS (the NETLIB backend) and LAPACK (the fallback)
# are targets in subdirectories, and LAPACK's own CMake sets -O2, so R's
# optimisation level is appended to them in deferred calls.  FlexiBLAS also
# adds -ffloat-store to its BLAS and stack protection everywhere; they do not
# change results but made its BLAS two to four times slower than R's, so they
# are switched off again.  -frecursive stays: it keeps local arrays off
# static storage, which LAPACK needs to be called from several threads.
# FlexiBLAS adds those flags for GNU compilers only, and R does without
# -ffloat-store for dlamch.f with LLVM, so with flang only the optimisation
# levels remain.
cat > $BHOME/build/rflags.cmake <<'EOF'
cmake_language(DEFER CALL set_property TARGET flexiblas_netlib_objs APPEND PROPERTY COMPILE_OPTIONS "$<$<COMPILE_LANGUAGE:Fortran>:-O2>")
cmake_language(DEFER CALL set_property TARGET flexiblas_fallback_lapack_objs APPEND PROPERTY COMPILE_OPTIONS "$<$<COMPILE_LANGUAGE:Fortran>:-O3>")
EOF
if [ ${RTARGET} != "aarch64" ] ; then
cat >> $BHOME/build/rflags.cmake <<'EOF'
cmake_language(DEFER CALL set_property TARGET flexiblas_netlib_objs APPEND PROPERTY COMPILE_OPTIONS "$<$<COMPILE_LANGUAGE:Fortran>:-fno-float-store>")
cmake_language(DEFER CALL set_property TARGET flexiblas_netlib_objs APPEND PROPERTY COMPILE_OPTIONS "$<$<COMPILE_LANGUAGE:Fortran>:-fno-stack-protector>")
cmake_language(DEFER CALL set_property TARGET flexiblas_netlib_objs APPEND PROPERTY COMPILE_OPTIONS "$<$<COMPILE_LANGUAGE:Fortran>:-fno-stack-clash-protection>")
cmake_language(DEFER CALL set_property TARGET flexiblas_fallback_lapack_objs APPEND PROPERTY COMPILE_OPTIONS "$<$<COMPILE_LANGUAGE:Fortran>:-fno-stack-protector>")
cmake_language(DEFER CALL set_property TARGET flexiblas_fallback_lapack_objs APPEND PROPERTY COMPILE_OPTIONS "$<$<COMPILE_LANGUAGE:Fortran>:-fno-stack-clash-protection>")
cmake_language(DEFER CALL set_property SOURCE ${CMAKE_SOURCE_DIR}/contributed/lapack-3.12.1/INSTALL/dlamch.f
  DIRECTORY ${CMAKE_SOURCE_DIR}/contributed/lapack-3.12.1/SRC APPEND PROPERTY COMPILE_OPTIONS -ffloat-store)
EOF
fi

# The C and Fortran flags are CMake's Release defaults with R's EOPTS; they
# reach FlexiBLAS itself, the BLAS and LAPACK get R's flags above.
# ZDOTC_MKL_EXITCODE answers a try_run that cannot run when cross-compiling:
# OpenBLAS built with gfortran, or with flang on aarch64, returns complex
# values the GNU way.
${TRIPLET}-cmake -S . -B build64 \
  -DCMAKE_BUILD_TYPE=Release \
  "-DCMAKE_C_FLAGS_RELEASE=-O3 -DNDEBUG $EOPTS" \
  "-DCMAKE_Fortran_FLAGS_RELEASE=-O3 $EOPTS" \
  -DCMAKE_PROJECT_FlexiBLAS_INCLUDE=$BHOME/build/rflags.cmake \
  -DCMAKE_INSTALL_PREFIX=$BINST \
  -DCMAKE_INSTALL_BINDIR=$BINDIR \
  -DBUILD_SHARED_LIBS=ON \
  -DINTEGER8=OFF \
  -DTESTS=OFF \
  -DEXAMPLES=OFF \
  -DLTO=OFF \
  -DBLAS_AUTO_DETECT=OFF \
  "-DEXTRA=$EXTRA" \
  "-DOPENBLAS_LIBRARY=-Wl,--whole-archive;$TLIB/libopenblas.a;-Wl,--no-whole-archive;$FLIBS" \
  -DOPENBLAS_LINKER_FLAGS=-fopenmp \
  "${PTHOPTS[@]}" \
  -DZDOTC_MKL_EXITCODE=1 \
  "-DCMAKE_SHARED_LINKER_FLAGS=$LDEXCLUDE" 2>&1 | tee configure64.out
make -C build64 -j 2>&1 | tee make64.out
make -C build64 install 2>&1 | tee install64.out
cp configure64.out make64.out install64.out $BHOME/build
# the libopenblas.a inside OPENBLAS-PTHREADS is not installed

# pkg-config files, headers, documentation and import libraries are not
# needed, except libflexiblas.dll.a: R's build reads from it the LAPACK
# entry points FlexiBLAS has
cd $BINST
rm -f `find . -name "*.a" ! -name libflexiblas.dll.a`
rm -rf $BINDIR/pkgconfig include share
${TRIPLET}-strip `find . -name "*.dll"`

# The bundle is in FlexiBLAS
cd $BHOME
zip -r FlexiBLAS FlexiBLAS
cp FlexiBLAS.zip build

# Sanity check
find FlexiBLAS | md5sum
du FlexiBLAS -ksk
${TRIPLET}-objdump -p FlexiBLAS/$BINDIR/libflexiblas.dll | grep 'DLL Name'
# runtime symbols that should not be in the export table
${TRIPLET}-objdump -p FlexiBLAS/$BINDIR/libflexiblas.dll | grep -c -E '\] *(omp_|GOMP_|__stack_chk|_gfortran_|_Fortran|dl(open|sym|close|error)$)' || true

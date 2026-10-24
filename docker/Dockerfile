# R's MXE tree for Rtools45 (R-dev SVN, ucrt3/toolchain_libs/mxe), set up
# from CRAN's pre-built toolchain tarballs as described in R-core's howto,
# section "Setting up MXE build from pre-built tarballs". Packages are then
# rebuilt with "make PKG" (scripts/build-mxe.sh).
FROM ubuntu:24.04

# Host dependencies as in toolchain_libs/build_in_docker.sh, plus svn/zstd.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        autoconf automake autopoint bash bison bzip2 ca-certificates flex g++ \
        gettext git gperf intltool libltdl-dev libssl-dev libtool-bin \
        libxml-parser-perl lzip make openssl p7zip-full patch perl python3 \
        python3-mako python3-packaging python3-setuptools python-is-python3 \
        ruby sed sqlite3 subversion texinfo unzip wget xz-utils zstd curl innoextract \
 && rm -rf /var/lib/apt/lists/*

# The MXE revision that built the Rtools45 tarballs used below.
ARG MXE_REV=6768
RUN svn checkout -q -r $MXE_REV \
        https://svn.r-project.org/R-dev-web/trunk/WindowsBuilds/winutf8/ucrt3/toolchain_libs/mxe /opt/mxe

WORKDIR /opt/mxe
RUN mkdir usr && cd usr \
 && for k in cross full; do \
        f=rtools45-toolchain-libs-$k-$MXE_REV.tar.zst; \
        wget -q https://cran.r-project.org/bin/windows/Rtools/rtools45/files/$f \
        && tar --zstd -xf $f && rm $f; \
    done \
 && mkdir -p /usr/lib/mxe && ln -s /opt/mxe/usr /usr/lib/mxe/usr

# The full tarball's target bin/ holds Windows binutils (as.exe, ...); the
# cross compiler must find the Linux ones there under their plain names.
RUN cd usr/x86_64-w64-mingw32.static.posix/bin \
 && for t in as ld ar nm ranlib objdump dlltool strip; do \
        [ -e $t ] || ln -s ../../bin/x86_64-w64-mingw32.static.posix-$t $t; \
    done

RUN make ccache > /dev/null

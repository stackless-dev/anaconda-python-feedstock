#!/bin/bash

# The LTO/PGO information was sourced from @pitrou and the Debian rules file in:
# http://http.debian.net/debian/pool/main/p/python3.6/python3.6_3.6.2-2.debian.tar.xz
# https://packages.debian.org/source/sid/python3.6
# or:
# http://bazaar.launchpad.net/~doko/python/pkg3.5-debian/view/head:/rules#L255
# .. but upstream regrtest.py now has --pgo (since >= 3.6) and skips tests that are:
# "not helpful for PGO".

VER=${PKG_VERSION%.*}
CONDA_FORGE=no

# Remove bzip2's shared library if present,
# as we only want to link to it statically.
# This is important in cases where conda
# tries to update bzip2.
find "${PREFIX}/lib" -name "libbz2*${SHLIB_EXT}*" | xargs rm -fv {}

# Prevent lib/python${VER}/_sysconfigdata_*.py from ending up with full paths to these things
# in _build_env because _build_env will not get found during prefix replacement, only _h_env_placeh ...
AR=$(basename "${AR}")

# CC must contain the string 'gcc' or else distutils thinks it is on macOS and uses '-R' to set rpaths.
if [[ ${HOST} =~ .*darwin.* ]]; then
  CC=$(basename "${CC}")
else
  CC=$(basename "${GCC}")
fi
CXX=$(basename "${CXX}")
RANLIB=$(basename "${RANLIB}")
READELF=$(basename "${READELF}")

if [[ ${HOST} =~ .*darwin.* ]]; then
  LDFLAGS=${LDFLAGS_CC}
fi

if [[ ${HOST} =~ .*darwin.* ]] && [[ -n ${CONDA_BUILD_SYSROOT} ]]; then
  # Python's setup.py will figure out that this is a macOS sysroot.
  CFLAGS="-isysroot ${CONDA_BUILD_SYSROOT} "${CFLAGS}
  LDFLAGS="-isysroot ${CONDA_BUILD_SYSROOT} "${LDFLAGS}
  CPPFLAGS="-isysroot ${CONDA_BUILD_SYSROOT} "${CPPFLAGS}
fi

# Debian uses -O3 then resets it at the end to -O2 in _sysconfigdata.py
export CPPFLAGS=$(echo "${CPPFLAGS}" | sed "s/-O2/-O3/g")
export CFLAGS=$(echo "${CFLAGS}" | sed "s/-O2/-O3/g")
export CXXFLAGS=$(echo "${CXXFLAGS}" | sed "s/-O2/-O3/g")
export LDFLAGS

if [[ ${CONDA_FORGE} == yes ]]; then
  ${SYS_PYTHON} ${RECIPE_DIR}/brand_python.py
fi

_buildd_static=build-static
_buildd_shared=build-shared
LTO_CFLAGS="-g -flto -fuse-linker-plugin"

# Remove ensurepip stubs.
rm -rf Lib/ensurepip

if [[ ${HOST} =~ .*darwin.* ]]; then
  sed -i -e "s/@OSX_ARCH@/$ARCH/g" Lib/distutils/unixccompiler.py
fi

if [[ "${BUILD}" != "${HOST}" ]] && [[ -n "${BUILD}" ]] && [[ -n "${HOST}" ]]; then
  # Build the exact same Python for the build machine. It would be nice (and might be
  # possible already?) to be able to make this just an 'exact' pinned build dependency
  # of a split-package?
  BUILD_PYTHON_PREFIX=${PWD}/build-python-install
  mkdir build-python-build
  pushd build-python-build
    (unset CPPFLAGS LDFLAGS;
     export CC=/usr/bin/gcc \
            CXX=/usr/bin/g++ \
            CPP=/usr/bin/cpp \
            CFLAGS="-O2" \
            AR=/usr/bin/ar \
            RANLIB=/usr/bin/ranlib \
            LD=/usr/bin/ld && \
      ../configure --build=${BUILD} \
                   --host=${BUILD} \
                   --prefix=${BUILD_PYTHON_PREFIX} \
                   --with-ensurepip=no && \
      make && \
      make install)
    export PATH=${BUILD_PYTHON_PREFIX}/bin:${PATH}
    ln -s ${BUILD_PYTHON_PREFIX}/bin/python${VER} ${BUILD_PYTHON_PREFIX}/bin/python
  popd
  echo "ac_cv_file__dev_ptmx=yes"        > config.site
  echo "ac_cv_file__dev_ptc=yes"        >> config.site
  echo "ac_cv_pthread=yes"              >> config.site
  echo "ac_cv_little_endian_double=yes" >> config.site
  export CONFIG_SITE=${PWD}/config.site
  # This is needed for libffi:
  export PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig
  _OPTIMIZED=1
else
  _OPTIMIZED=1
fi

# This causes setup.py to query the sysroot directories from the compiler, something which
# IMHO should be done by default anyway with a flag to disable it to workaround broken ones.
# Technically, setting _PYTHON_HOST_PLATFORM causes setup.py to consider it cross_compiling
if [[ -n ${HOST} ]]; then
  if [[ ${HOST} =~ .*darwin.* ]]; then
    # Even if BUILD is .*darwin.* you get better isolation by cross_compiling (no /usr/local)
    export _PYTHON_HOST_PLATFORM=darwin
  else
    IFS='-' read -r host_arch host_vendor host_os host_libc <<<"${HOST}"
    export _PYTHON_HOST_PLATFORM=${host_os}-${host_arch}
  fi
fi

# Not used at present but we should run 'make test' and finish up TESTOPTS (see debians rules).
declare -a TEST_EXCLUDES
TEST_EXCLUDES+=(test_ensurepip test_venv)
TEST_EXCLUDES+=(test_tcl test_codecmaps_cn test_codecmaps_hk
                test_codecmaps_jp test_codecmaps_kr test_codecmaps_tw
                test_normalization test_ossaudiodev test_socket)
if [[ ! -f /dev/dsp ]]; then
  TEST_EXCLUDES+=(test_linuxaudiodev test_ossaudiodev)
fi
# hangs on Aarch64, see LP: #1264354
if [[ ${CC} =~ .*-aarch64.* ]]; then
  TEST_EXCLUDES+=(test_faulthandler)
fi
if [[ ${CC} =~ .*-arm.* ]]; then
  TEST_EXCLUDES+=(test_ctypes)
  TEST_EXCLUDES+=(test_compiler)
fi

declare -a _common_configure_args
_common_configure_args+=(--prefix=${PREFIX})
_common_configure_args+=(--build=${BUILD})
_common_configure_args+=(--host=${HOST})
_common_configure_args+=(--enable-ipv6)
_common_configure_args+=(--with-ensurepip=no)
_common_configure_args+=(--with-computed-gotos)
_common_configure_args+=(--with-system-ffi)
_common_configure_args+=(--enable-loadable-sqlite-extensions)
_common_configure_args+=(--with-tcltk-includes="-I${PREFIX}/include")
_common_configure_args+=("--with-tcltk-libs=-L${PREFIX}/lib -ltcl8.6 -ltk8.6")

mkdir -p ${_buildd_shared}
pushd ${_buildd_shared}
  ../configure "${_common_configure_args[@]}" \
               --enable-shared
popd

# Add more optimization flags for the static Python interpreter:
declare -a _extra_opts
if [[ ${_OPTIMIZED} == 1 ]]; then
  _extra_opts+=(--enable-optimizations)
  _extra_opts+=(--with-lto)
  _MAKE_TARGET=profile-opt
  if [[ ${CC} =~ .*gcc.* ]]; then
    LTO_CFLAGS="${LTO_CFLAGS} -ffat-lto-objects"
  fi
else
  _MAKE_TARGET=
fi

mkdir -p ${_buildd_static}
pushd ${_buildd_static}
  ../configure "${_common_configure_args[@]}" \
               "${_extra_opts[@]}" \
               --disable-shared
popd

make -j${CPU_COUNT} -C ${_buildd_static} \
        EXTRA_CFLAGS="${EXTRA_CFLAGS}" \
        ${_MAKE_TARGET}

make -j${CPU_COUNT} -C ${_buildd_shared} \
        EXTRA_CFLAGS="${EXTRA_CFLAGS}"
# build a static library with PIC objects
make -j${CPU_COUNT} -C ${_buildd_shared} \
        EXTRA_CFLAGS="${EXTRA_CFLAGS}" \
        LIBRARY=libpython${VER}m-pic.a libpython${VER}m-pic.a

if [[ ${_OPTIMIZED} == 1 ]]; then
  make -C ${_buildd_static} install
  SYSCONFIG=$(find ${_buildd_shared}/$(cat ${_buildd_shared}/pybuilddir.txt) -name "_sysconfigdata*.py")
  cat ${SYSCONFIG} | ${SYS_PYTHON} "${RECIPE_DIR}"/replace-word-pairs.py \
    "-O3" "-O2"  \
    "${LTO_CFLAGS}" ""  \
    "RUNSHARED *=.*" "RUNSHARED="  \
    "-fprofile-use *-fprofile-correction" ""  \
    "-L." ""
      > ${PREFIX}/lib/python${VER}/$(basename ${SYSCONFIG})
  # Check that our differences took.
  diff -urN ${SYSCONFIG} ${PREFIX}/lib/python${VER}/$(basename ${SYSCONFIG})
  # Install the shared library
  if [[ ${HOST} =~ .*linux.* ]]; then
    cp -p ${_buildd_shared}/libpython${VER}m${SHLIB_EXT}.1.0 ${PREFIX}/lib/
    ln -sf ${PREFIX}/lib/libpython${VER}m${SHLIB_EXT}.1.0 ${PREFIX}/lib/libpython${VER}m${SHLIB_EXT}.1
    ln -sf ${PREFIX}/lib/libpython${VER}m${SHLIB_EXT}.1 ${PREFIX}/lib/libpython${VER}m${SHLIB_EXT}
  elif [[ ${HOST} =~ .*darwin.* ]]; then
    cp -p ${_buildd_shared}/libpython${VER}m${SHLIB_EXT} ${PREFIX}/lib/
  fi
else
  make -C ${_buildd_shared} install
fi

# Python installs python${VER}m and python${VER}, one as a hardlink to the other. conda-build breaks these
# by copying. Since the executable may be static it may be very large so change one to be a symlink
# of the other. In this case, python${VER}m will be the symlink.
if [[ -f ${PREFIX}/bin/python${VER}m ]]; then
  rm -f ${PREFIX}/bin/python${VER}m
  ln -s ${PREFIX}/bin/python${VER} ${PREFIX}/bin/python${VER}m
fi
ln -s ${PREFIX}/bin/python${VER} ${PREFIX}/bin/python
ln -s ${PREFIX}/bin/pydoc${VER} ${PREFIX}/bin/pydoc

# Remove test data to save space
# Though keep `support` as some things use that.
# TODO :: Make a subpackage for this once we implement multi-level testing.
pushd ${PREFIX}/lib/python${VER}
  mkdir test_keep
  mv test/__init__.py test/support test/test_support* test/test_script_helper* test_keep/
  rm -rf test */test
  mv test_keep test
popd

# Size reductions:
pushd ${PREFIX}
  if [[ -f lib/libpython${VER}m.a ]]; then
    chmod +w lib/libpython${VER}m.a
    if [[ -n ${HOST} ]]; then
      ${HOST}-strip -S lib/libpython${VER}m.a
    else
      strip -S lib/libpython${VER}m.a
    fi
  fi
  CONFIG_LIBPYTHON=$(find lib/python${VER}/config-${VER}m* -name "libpython${VER}m.a")
  if [[ -f lib/libpython${VER}m.a ]] && [[ -f ${CONFIG_LIBPYTHON} ]]; then
    chmod +w ${CONFIG_LIBPYTHON}
    rm ${CONFIG_LIBPYTHON}
    ln -s ../../libpython${VER}m.a ${CONFIG_LIBPYTHON}
  fi
popd

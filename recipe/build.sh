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

# For debugging builds, set this to 0 to disable profile-guided optimization
if [[ ${DEBUG_C} == yes ]]; then
  _OPTIMIZED=no
else
  _OPTIMIZED=yes
fi

declare -a _dbg_opts
if [[ ${DEBUG_PY} == yes ]]; then
  # This Python will not be usable with non-debug Python modules.
  _dbg_opts+=(--with-pydebug)
  DBG=d
else
  DBG=
fi

# This is the mechanism by which we fall back to default gcc, but having it defined here
# would probably break the build by using incorrect settings and/or importing files that
# do not yet exist.
unset _PYTHON_SYSCONFIGDATA_NAME
unset _CONDA_PYTHON_SYSCONFIGDATA_NAME

# Remove bzip2's shared library if present,
# as we only want to link to it statically.
# This is important in cases where conda
# tries to update bzip2.
find "${PREFIX}/lib" -name "libbz2*${SHLIB_EXT}*" | xargs rm -fv {}

# Prevent lib/python3.6/_sysconfigdata_m_linux_arm-linux-gnueabi.py from ending up with full paths to these
# things in _build_env because _build_env will not get found during prefix replacement, only _h_env_placeh ...
AR=$(basename "${AR}")
# CC must contain the string 'gcc' or else distutils thinks it is on macOS and uses '-R' to set rpaths.
CC=$(basename "${GCC}")
CXX=$(basename "${CXX}")
RANLIB=$(basename "${RANLIB}")
READELF=$(basename "${READELF}")

${SYS_PYTHON} ${RECIPE_DIR}/brand_python.py

# CC must contain the string 'gcc' or else distutils thinks it is on macOS and uses '-R' to set rpaths.
if [[ ${HOST} =~ .*darwin.* ]]; then
  CC=$(basename "${CC}")
else
  CC=$(basename "${GCC}")
fi
CXX=$(basename "${CXX}")
RANLIB=$(basename "${RANLIB}")
READELF=$(basename "${READELF}")

if [[ ${HOST} =~ .*darwin.* ]] && [[ -n ${CONDA_BUILD_SYSROOT} ]]; then
  # Python's setup.py will figure out that this is a macOS sysroot.
  CFLAGS="-isysroot ${CONDA_BUILD_SYSROOT} "${CFLAGS}
  LDFLAGS="-isysroot ${CONDA_BUILD_SYSROOT} "${LDFLAGS}
  CPPFLAGS="-isysroot ${CONDA_BUILD_SYSROOT} "${CPPFLAGS}
fi

# Debian uses -O3 then resets it at the end to -O2 in _sysconfigdata.py
if [[ ${_OPTIMIZED} = yes ]]; then
  CPPFLAGS=$(echo "${CPPFLAGS}" | sed "s/-O2/-O3/g")
  CFLAGS=$(echo "${CFLAGS}" | sed "s/-O2/-O3/g")
  CXXFLAGS=$(echo "${CXXFLAGS}" | sed "s/-O2/-O3/g")
fi

if [[ ${CONDA_FORGE} == yes ]]; then
  ${SYS_PYTHON} ${RECIPE_DIR}/brand_python.py
fi

_buildd_static=build-static
_buildd_shared=build-shared
declare -a LTO_CFLAGS

CPPFLAGS=${CPPFLAGS}" -I${PREFIX}/include"

re='^(.*)(-I[^ ]*)(.*)$'
if [[ ${CFLAGS} =~ $re ]]; then
  CFLAGS="${BASH_REMATCH[1]}${BASH_REMATCH[3]}"
fi

export CPPFLAGS CFLAGS CXXFLAGS LDFLAGS

if [[ ${HOST} =~ .*darwin.* ]]; then
  sed -i -e "s/@OSX_ARCH@/$ARCH/g" Lib/distutils/unixccompiler.py
elif [ $(uname) == Linux ]; then
  export CPPFLAGS="-I$PREFIX/include"
  export LDFLAGS="-L$PREFIX/lib -Wl,-rpath=$PREFIX/lib,--no-as-needed"
fi

if [[ "${BUILD}" != "${HOST}" ]]; then
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
    ln -s ${BUILD_PYTHON_PREFIX}/bin/python3.6 ${BUILD_PYTHON_PREFIX}/bin/python
  popd
  echo "ac_cv_file__dev_ptmx=yes"        > config.site
  echo "ac_cv_file__dev_ptc=yes"        >> config.site
  echo "ac_cv_pthread=yes"              >> config.site
  echo "ac_cv_little_endian_double=yes" >> config.site
  export CONFIG_SITE=${PWD}/config.site
  # This is needed for libffi:
  export PKG_CONFIG_PATH=${PREFIX}/lib/pkgconfig

  _OPTIMISED=1
else
  _OPTIMISED=1
fi

declare -a _extra_opts
if [[ ${_OPTIMIZED} == 1 ]]; then
  _extra_opts+=(--enable-optimizations)
  _extra_opts+=(--enable-lto)
  _MAKE_TARGET=profile-opt
else
  _MAKE_TARGET=
fi


# This causes setup.py to query the sysroot directories from the compiler, something which
# IMHO should be done by default anyway with a flag to disable it to workaround broken ones.
if [[ -n ${HOST} ]]; then
  IFS='-' read -r host_arch host_vendor host_os host_libc <<<"${HOST}"
  export _PYTHON_HOST_PLATFORM=${host_os}-${host_arch}
fi

./configure --build=${BUILD} \
            --host=${HOST} \
            --enable-shared \
            --enable-ipv6 \
            --with-ensurepip=no \
            --prefix=$PREFIX \
            --with-system-ffi \
            --with-tcltk-includes="-I$PREFIX/include" \
            --with-tcltk-libs="-L$PREFIX/lib -ltcl8.6 -ltk8.6" \
            --enable-loadable-sqlite-extensions \
            "${_extra_opts[@]}"

make ${_MAKE_TARGET}
make install
ln -s $PREFIX/bin/python3.6 $PREFIX/bin/python
ln -s $PREFIX/bin/pydoc3.6 $PREFIX/bin/pydoc

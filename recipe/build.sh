#!/bin/bash

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

# Remove test data to save space.
# Though keep `support` as some things use that.
mkdir Lib/test_keep
mv Lib/test/support Lib/test_keep/support
rm -rf Lib/test Lib/*/test
mv Lib/test_keep Lib/test

# Remove ensurepip stubs.
rm -rf Lib/ensurepip

if [ $(uname) == Darwin ]; then
  export CFLAGS="-I$PREFIX/include $CFLAGS"
  export LDFLAGS="-Wl,-rpath,$PREFIX/lib -L$PREFIX/lib -headerpad_max_install_names $LDFLAGS"
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

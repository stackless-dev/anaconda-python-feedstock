#!/bin/bash

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
CC=$(basename "${GCC}")
CXX=$(basename "${CXX}")
RANLIB=$(basename "${RANLIB}")
READELF=$(basename "${READELF}")

# Debian uses -O3 then resets it at the end to -O2 in _sysconfigdata.py
export CFLAGS=$(echo "${CFLAGS}" | sed "s/-O2/-O3/g")
export CXXFLAGS=$(echo "${CXXFLAGS}" | sed "s/-O2/-O3/g")

if [[ ${CONDA_FORGE} == yes ]]; then
  ${SYS_PYTHON} ${RECIPE_DIR}/brand_python.py
fi

# Remove ensurepip stubs.
rm -rf Lib/ensurepip

export CPPFLAGS=${CPPFLAGS}" -I${PREFIX}/include"
export LDFLAGS=${LDFLAGS}" -Wl,-rpath,${PREFIX}/lib -L${PREFIX}/lib"
if [[ $(uname) == Darwin ]]; then
  sed -i -e "s/@OSX_ARCH@/$ARCH/g" Lib/distutils/unixccompiler.py
  UNICODE=ucs2
elif [[ $(uname) == Linux ]]; then
  export LDFLAGS=${LDFLAGS}" -Wl,--no-as-needed"
  UNICODE=ucs4
fi

declare -a _common_configure_args
_common_configure_args+=(--prefix=${PREFIX})
_common_configure_args+=(--build=${BUILD})
_common_configure_args+=(--host=${HOST})
_common_configure_args+=(--enable-ipv6)
_common_configure_args+=(--enable-unicode=${UNICODE})
_common_configure_args+=(--with-computed-gotos)
_common_configure_args+=(--with-system-ffi)
_common_configure_args+=(--with-tcltk-includes="-I${PREFIX}/include")
_common_configure_args+=("--with-tcltk-libs=-L${PREFIX}/lib -ltcl8.6 -ltk8.6")
./configure "${_common_configure_args[@]}" \
            --enable-shared
make -j${CPU_COUNT}
make install

# Remove test data to save space
# Though keep `support` as some things use that.
# TODO :: Make a subpackage for this once we implement multi-level testing.
pushd ${PREFIX}/lib/python${VER}
  mkdir test_keep
  mv test/__init__.py test/test_support* test/script_helper* test_keep/
  rm -rf test */test
  mv test_keep test
popd

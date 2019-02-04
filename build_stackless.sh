#!/bin/sh

set -x
set -e

# A simple script to build Stackless-Python

ver="3.7"
recipe="recipe"

# in case someone enables branding
export python_branding="| packaged by the Stackless team |"

# Ensure recipe is availabe
test -f "$recipe/meta.yaml"

# Ensure conda is availabe
command -v conda
conda_dir="$(command -v conda)"
conda_dir="${conda_dir%/*}"
test -f "$conda_dir/activate"

# make sure conda-build is available in the base environment
# I obverved failures on Windows without it
conda install --yes conda-build

# clean up
conda remove --yes --name buildslp --all || :
conda remove --yes --name testslp --all || :
conda config --env --remove channels local || :
conda config --env --remove channels conda-forge || :
conda create --yes --name buildslp

# Activate environment "buildslp"
. "$conda_dir/activate" buildslp

conda config --env --set add_pip_as_python_dependency False
conda config --env --add channels stackless
conda update --all --yes
conda install --yes conda-build

# Stackless Python source archives are "tar.xz" files. Therefore we need
# the command "unxz" to extract them.
if ! command -v unxz ; then
  conda install --yes xz
  # conda "unxz" does not support the Option "-f".
  # xz.exe renamed to unxz.exe does.
  xz="$(command -v xz)"
  unxz="$(command -v unxz)"
  if [ -f "$xz".exe ] ; then
    xz="$xz".exe
	unxz="$unxz".exe
  fi
  cp "$xz" "$unxz" || :
fi

# See recipe/run_test.py for details
export tk='8.6'
export openssl=''

conda build purge
conda build "$recipe" --python="$ver"

. "$conda_dir/deactivate"

conda create --yes --name testslp

. "$conda_dir/activate" testslp

conda config --env --append channels stackless
conda update --all --yes
conda install --show-channel-urls --use-local --yes stackless python="$ver"

python -c 'import stackless'

cat <<EOF
To upload the result to anaconda.org/stackless use
$ conda install -c anaconda anaconda-client
$ anaconda login --username stackless
$ anaconda upload ....
EOF

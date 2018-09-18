#!/bin/sh

set -x
set -e

# A simple script to build Stackless-Python

ver="3.6"
recipe="recipe"

# Ensure recipe is availabe
test -f "$recipe/meta.yaml"

# Ensure conda is availabe
command -v conda
conda_dir="$(command -v conda)"
conda_dir="${conda_dir%/*}"
test -f "$conda_dir/activate"

conda remove --yes --name buildslp --all || :
conda remove --yes --name testslp --all || :
conda config --env --remove channels local || :
conda create --yes --name buildslp

. "$conda_dir/activate" buildslp

conda config --env --set add_pip_as_python_dependency False
conda config --env --add channels stackless
conda update --all --yes
conda install --yes python="$ver" conda-build

conda build purge
conda build "$recipe"

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

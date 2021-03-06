#!/bin/bash

set -e

for i in $*; do
  case $i in
    --pycbc-container=*) PYCBC_CONTAINER="`echo $i|sed 's/^--pycbc-container=//'`";;
    --pull-request=*) TRAVIS_PULL_REQUEST="`echo $i|sed 's/^--pull-request=//'`";;
    --lalsuite-hash=*) LALSUITE_HASH="`echo $i|sed 's/^--lalsuite-hash=//'`";;
    --commit=*) TRAVIS_COMMIT="`echo $i|sed 's/^--commit=//'`";;
    --secure=*) TRAVIS_SECURE_ENV_VARS="`echo $i|sed 's/^--secure=//'`";;
    --tag=*) TRAVIS_TAG="`echo $i|sed 's/^--tag=//'`";;
    *) echo -e "unknown option '$i', valid are:\n$usage">&2; exit 1;;
  esac
done

# determine the pycbc git branch and origin
if test x$TRAVIS_PULL_REQUEST = "xfalse" ; then
    PYCBC_CODE="--pycbc-commit=${TRAVIS_COMMIT}"
else
    PYCBC_CODE="--pycbc-fetch-ref=refs/pull/${TRAVIS_PULL_REQUEST}/merge"
fi

# set the lalsuite checkout to use

if [ "x$TRAVIS_TAG" == "x" ] ; then
  TRAVIS_TAG="master"
  RSYNC_OPTIONS="--delete"
else
  RSYNC_OPTIONS=""
fi

echo -e "\\n>> [`date`] Inside container ${PYCBC_CONTAINER}"
echo -e "\\n>> [`date`] Release tag is ${TRAVIS_TAG}"
echo -e "\\n>> [`date`] Using PyCBC code ${PYCBC_CODE}"
echo -e "\\n>> [`date`] Using lalsuite hash ${LALSUITE_HASH}"
echo -e "\\n>> [`date`] Travis pull request is ${TRAVIS_PULL_REQUEST}"
echo -e "\\n>> [`date`] Travis commit is ${TRAVIS_COMMIT}"
echo -e "\\n>> [`date`] Travis secure env is ${TRAVIS_SECURE_ENV_VARS}"
echo -e "\\n>> [`date`] Travis tag is ${TRAVIS_TAG}"

if [ "x${TRAVIS_SECURE_ENV_VARS}" == "xtrue" ] ; then
  mkdir -p ~/.ssh
  cp /pycbc/.ssh/* ~/.ssh
  chmod 600 ~/.ssh/id_rsa
fi

if [ "x${PYCBC_CONTAINER}" == "xpycbc_inspiral_bundle" ] ; then
  echo -e "\\n>> [`date`] Building pycbc_inspiral bundle for CentOS 6"

  # create working dir for build script
  BUILD=/pycbc/build
  mkdir -p ${BUILD}
  export PYTHONUSERBASE=${BUILD}/.local
  export XDG_CACHE_HOME=${BUILD}/.cache

  # Autoconf needs m4
  wget -O m4-1.4.9.tar.gz http://ftp.gnu.org/gnu/m4/m4-1.4.9.tar.gz
  tar -zvxf m4-1.4.9.tar.gz
  cd m4-1.4.9
  ./configure
  make
  make install
  cd ..

  # Build new autoconf
  curl -L -O http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.gz
  tar zxf autoconf-2.69.tar.gz
  cd autoconf-2.69
  ./configure
  make && make install
  cd ..

  # get library to build optimized pycbc_inspiral bundle
  wget_opts="-c --passive-ftp --no-check-certificate --tries=5 --timeout=30 --no-verbose"
  primary_url="https://git.ligo.org/ligo-cbc/pycbc-software/raw/"
  secondary_url="https://www.atlas.aei.uni-hannover.de/~dbrown"
  pushd /pycbc
  for p in "cea5bd67440f6c3195c555a388def3cc6d695a5c/x86_64/composer_xe_2015.0.090/composer_xe_2015.0.090.tar.gz" "2d7e4a4f2f1503db5b93d70907fa24ad54bffbcb/travis/testbank_TF2v4ROM.hdf" ; do
    set +e
    test -r `basename $p` || wget $wget_opts ${primary_url}/${p}
    set -e
    test -r `basename $p` || wget $wget_opts ${secondary_url}/${p}
  done
  popd

  # run the einstein at home build and test script
  echo -e "\\n>> [`date`] Running pycbc_build_eah.sh"
  pushd ${BUILD}
  /pycbc/tools/einsteinathome/pycbc_build_eah.sh --lalsuite-commit=${LALSUITE_HASH} ${PYCBC_CODE} --clean-pycbc --silent-build --download-url=https://git.ligo.org/ligo-cbc/pycbc-software/raw/710a51f4770cbba77f61dfb798472bebe6c43d38/travis --with-extra-approximant='SPAtmplt:mtotal<4' --with-extra-approximant='SEOBNRv4_ROM:else'  --with-extra-approximant=--use-compressed-waveforms --with-extra-libs=file:///pycbc/composer_xe_2015.0.090.tar.gz --processing-scheme=mkl --with-extra-bank=/pycbc/testbank_TF2v4ROM.hdf

  if [ "x${TRAVIS_SECURE_ENV_VARS}" == "xtrue" ] ; then
    echo -e "\\n>> [`date`] Deploying pycbc_inspiral bundle"
    BUNDLE_DEST=/home/pycbc/ouser.ligo/ligo/deploy/sw/pycbc/x86_64_rhel_6/bundle/${TRAVIS_TAG}
    echo -e "\\n>> [`date`] Deploying pycbc_inspiral bundle to sugwg-condor.phy.syr.edu"
    ssh pycbc@sugwg-condor.phy.syr.edu "mkdir -p ${BUNDLE_DEST}"
    scp ${BUILD}/pycbc-build/environment/dist/pycbc_inspiral_osg* pycbc@sugwg-condor.phy.syr.edu:${BUNDLE_DEST}/pycbc_inspiral
    if [ "x${TRAVIS_TAG}" != "xmaster" ] ; then
      PYCBC_INSPIRAL_SUFFIX="_osg_${TRAVIS_TAG}"
      BUNDLE_DEST=/home/login/ouser.ligo/ligo/deploy/sw/pycbc/x86_64_rhel_6/bundle/${TRAVIS_TAG}
      echo -e "\\n>> [`date`] Deploying pycbc_inspiral${PYCBC_INSPIRAL_SUFFIX} to CVMFS"
      ssh ouser.ligo@oasis-login.opensciencegrid.org "mkdir -p ${BUNDLE_DEST}"
      scp ${BUILD}/pycbc-build/environment/dist/pycbc_inspiral${PYCBC_INSPIRAL_SUFFIX} ouser.ligo@oasis-login.opensciencegrid.org:${BUNDLE_DEST}/pycbc_inspiral
      ssh ouser.ligo@oasis-login.opensciencegrid.org osg-oasis-update
    fi
    echo -e "\\n>> [`date`] pycbc_inspiral deployment complete"
  fi
  popd
fi

if [ "x${PYCBC_CONTAINER}" == "xpycbc_rhel_virtualenv" ] || [ "x${PYCBC_CONTAINER}" == "xpycbc_debian_virtualenv" ] ; then

  if [ "x${PYCBC_CONTAINER}" == "xpycbc_rhel_virtualenv" ] ; then
    echo -e "\\n>> [`date`] Building pycbc virtual environment for CentOS 7"
    ENV_OS="x86_64_rhel_7"
    yum -y install python2-pip python-setuptools which
    yum -y install curl
    curl http://download.pegasus.isi.edu/wms/download/rhel/7/pegasus.repo > /etc/yum.repos.d/pegasus.repo
    yum clean all
    yum makecache
    yum -y update
    yum -y install openssl-devel openssl-static
    yum -y install pegasus
    yum -y install ligo-proxy-utils
    yum -y install ecp-cookie-init
    yum -y install hdf5-static libxml2-static zlib-static libstdc++-static cfitsio-static glibc-static fftw-static gsl-static
  elif [ "x${PYCBC_CONTAINER}" == "xpycbc_debian_virtualenv" ] ; then
    echo -e "\\n>> [`date`] Building pycbc virtual environment for Debian"
    ENV_OS="x86_64_deb_8"
    apt-get update
    apt-get -y install python-pip
    apt-get -y install curl
    echo "deb http://software.ligo.org/gridtools/debian jessie main" > /etc/apt/sources.list.d/gridtools.list
    echo "deb http://software.ligo.org/lscsoft/debian jessie contrib" > /etc/apt/sources.list.d/lscsoft.list
    apt-get update
    apt-get --assume-yes --allow-unauthenticated install lscsoft-archive-keyring
    apt-get update
    curl -s -o pegasus-gpg.txt https://download.pegasus.isi.edu/pegasus/gpg.txt
    apt-key add pegasus-gpg.txt
    echo 'deb http://download.pegasus.isi.edu/wms/download/debian jessie main' > /etc/apt/sources.list.d/pegasus.list
    apt-get update
    apt-get -y install pegasus
    apt-get -y install ligo-proxy-utils
    apt-get -y install ecp-cookie-init
    apt-get -y install uuid-runtime
    apt-get -y install openssl swig
  else
    echo -e "\\n>> [`date`] Unknown operating system for virtual environment build"
    exit 1
  fi

  CVMFS_PATH=/cvmfs/oasis.opensciencegrid.org/ligo/sw/pycbc/${ENV_OS}/virtualenv
  mkdir -p ${CVMFS_PATH}

  VENV_PATH=${CVMFS_PATH}/pycbc-${TRAVIS_TAG}
  pip install virtualenv
  virtualenv ${VENV_PATH}
  echo 'export PYTHONUSERBASE=${VIRTUAL_ENV}/.local' >> ${VENV_PATH}/bin/activate
  echo "export XDG_CACHE_HOME=\${HOME}/cvmfs-pycbc-${TRAVIS_TAG}/.cache" >> ${VENV_PATH}/bin/activate
  source ${VENV_PATH}/bin/activate
  mkdir -p ${VIRTUAL_ENV}/.local
  echo -e "[easy_install]\\nzip_ok = false\\n" > ~/.pydistutils.cfg
  echo -e "[easy_install]\\nzip_ok = false\\n" > ${VIRTUAL_ENV}/.local/.pydistutils.cfg
    
  echo -e "\\n>> [`date`] Upgrading pip and setuptools"
  pip install --upgrade pip
  pip install six packaging appdirs
  pip install --upgrade setuptools

  echo -e "\\n>> [`date`] Installing base python packages required to build lalsuite"
  pip install "numpy>=1.6.4" "h5py>=2.5" unittest2 python-cjson Cython decorator
  echo -e "\\n>> [`date`] Installing scipy"
  pip install "scipy>=0.13.0" &>/dev/null

  echo -e "\\n>> [`date`] Installing LAL"
  mkdir -p ${VIRTUAL_ENV}/src
  cd ${VIRTUAL_ENV}/src
  git clone https://git.ligo.org/lscsoft/lalsuite.git lalsuite
  cd ${VIRTUAL_ENV}/src/lalsuite
  git checkout ${LALSUITE_HASH}
  ./00boot
  ./configure --prefix=${VIRTUAL_ENV} --enable-swig-python --disable-lalstochastic --disable-lalxml --disable-lalinference --disable-laldetchar --disable-lalapps 2>&1 | grep -v checking
  make -j 2 2>&1 | grep Entering
  make install 2>&1 | grep Entering

  # write PKG_CONFIG_PATH to activate
  sed -in "s/# unset PYTHONHOME/_OLD_PKG_CONFIG_PATH=\"\${PKG_CONFIG_PATH}\"\\
PKG_CONFIG_PATH=\"\${VIRTUAL_ENV}\/lib\/pkgconfig:\${PKG_CONFIG_PATH}\"\\
export PKG_CONFIG_PATH\\
\\
# unset PYTHONHOME/" ${VIRTUAL_ENV}/bin/activate

  # unset PKG_CONFIG_PATH in deactivate
  sed -in "s/unset _OLD_VIRTUAL_PYTHONHOME/unset _OLD_VIRTUAL_PYTHONHOME\\
    fi\\
    if ! [ -z \"\${_OLD_PKG_CONFIG_PATH+_}\" ]; then\\
        PKG_CONFIG_PATH=\"\$_OLD_PKG_CONFIG_PATH\"\\
        export PKG_CONFIG_PATH\\
        unset _OLD_PKG_CONFIG_PATH/" ${VIRTUAL_ENV}/bin/activate

  deactivate

  echo -e "\\n>> [`date`] Installing LALApps"
  source ${VENV_PATH}/bin/activate
  cd $VIRTUAL_ENV/src/lalsuite/lalapps
  if [ "x${PYCBC_CONTAINER}" == "xpycbc_rhel_virtualenv" ] ; then
    LIBS="-lhdf5_hl -lhdf5 -lcrypto -lssl -ldl -lz -lstdc++" ./configure --prefix=${VIRTUAL_ENV} --disable-lalxml --disable-lalinference --disable-lalburst --disable-lalpulsar --disable-lalstochastic 2>&1 | grep -v checking
  elif [ "x${PYCBC_CONTAINER}" == "xpycbc_debian_virtualenv" ] ; then
    LIBS="-L/usr/lib/x86_64-linux-gnu/hdf5/serial -lhdf5_hl -lhdf5 -lcrypto -lssl -ldl -lz -lstdc++" ./configure --prefix=${VIRTUAL_ENV} --disable-lalxml --disable-lalinference --disable-lalburst --disable-lalpulsar --disable-lalstochastic 2>&1 | grep -v checking
  fi
  cd $VIRTUAL_ENV/src/lalsuite/lalapps/src/lalapps
  make -j 2 2>&1 | grep Entering
  cd $VIRTUAL_ENV/src/lalsuite/lalapps/src/inspiral
  make -j 2 2>&1 | grep Entering
  make install 2>&1 | grep Entering

  echo -e "\\n>> [`date`] Install matplotlib 1.5.3"
  pip install 'matplotlib==1.5.3'

  echo -e "\\n>> [`date`] Installing PyCBC dependencies from requirements.txt"
  cd /pycbc
  pip install -r requirements.txt
  pip install -r companion.txt

  echo -e "\\n>> [`date`] Installing PyCBC from source"
  python setup.py install

  echo -e "\\n>> [`date`] Installing modules needed to build documentation"
  pip install "Sphinx>=1.5.0"
  pip install sphinx-rtd-theme
  pip install sphinxcontrib-programoutput

  echo -e "\\n>> [`date`] Installing ipython and jupyter"
  pip install ipython
  pip install jupyter
  pip install hide_code
  jupyter nbextension install --sys-prefix --py hide_code
  jupyter nbextension enable --sys-prefix --py hide_code
  jupyter serverextension enable --sys-prefix --py hide_code

  cat << EOF >> $VIRTUAL_ENV/bin/activate

# if a suitable MKL exists, set it up
if [ -f /opt/intel/composer_xe_2015/mkl/bin/mklvars.sh ] ; then
  # location on syracuse cluster
  . /opt/intel/composer_xe_2015/mkl/bin/mklvars.sh intel64
elif [ -f /opt/intel/2015/composer_xe_2015/mkl/bin/mklvars.sh ] ; then
  # location on atlas cluster
  . /opt/intel/2015/composer_xe_2015/mkl/bin/mklvars.sh intel64
elif [ -f /ldcg/intel/2017u0/compilers_and_libraries_2017.0.098/linux/mkl/bin/mklvars.sh ] ; then
  # location on cit cluster
  . /ldcg/intel/2017u0/compilers_and_libraries_2017.0.098/linux/mkl/bin/mklvars.sh intel64
fi

# Use the ROM data from CVMFS
export LAL_DATA_PATH=/cvmfs/oasis.opensciencegrid.org/ligo/sw/pycbc/lalsuite-extra/e02dab8c/share/lalsimulation
EOF

  deactivate

  if [ "x${TRAVIS_SECURE_ENV_VARS}" == "xtrue" ] ; then
    echo -e "\\n>> [`date`] Running test_coinc_search_workflow.sh"
    mkdir -p /pycbc/workflow-test
    pushd /pycbc/workflow-test
    /pycbc/tools/test_coinc_search_workflow.sh ${VENV_PATH} ${TRAVIS_TAG}
    popd
  fi

  if [ "x${TRAVIS_SECURE_ENV_VARS}" == "xtrue" ] ; then
    echo -e "\\n>> [`date`] Setting virtual environment permissions for deployment"
    find ${VENV_PATH} -type d -exec chmod go+rx {} \;
    chmod -R go+r ${VENV_PATH}

    echo -e "\\n>> [`date`] Deploying virtual environment ${VENV_PATH}"
    echo -e "\\n>> [`date`] Deploying virtual environment to sugwg-condor.phy.syr.edu"
    ssh pycbc@sugwg-condor.phy.syr.edu "mkdir -p /home/pycbc/ouser.ligo/ligo/deploy/sw/pycbc/${ENV_OS}/virtualenv/pycbc-${TRAVIS_TAG}"
    rsync --rsh=ssh $RSYNC_OPTIONS -qraz ${VENV_PATH}/ pycbc@sugwg-condor.phy.syr.edu:/home/pycbc/ouser.ligo/ligo/deploy/sw/pycbc/${ENV_OS}/virtualenv/pycbc-${TRAVIS_TAG}/
    if [ "x${TRAVIS_TAG}" != "xmaster" ] ; then
      echo -e "\\n>> [`date`] Deploying release ${TRAVIS_TAG} to CVMFS"
      # remove lalsuite source and deploy on cvmfs
      rm -rf ${VENV_PATH}/src/lalsuite
      ssh ouser.ligo@oasis-login.opensciencegrid.org "mkdir -p /home/login/ouser.ligo/ligo/deploy/sw/pycbc/${ENV_OS}/virtualenv/pycbc-${TRAVIS_TAG}"
      rsync --rsh=ssh $RSYNC_OPTIONS -qraz ${VENV_PATH}/ ouser.ligo@oasis-login.opensciencegrid.org:/home/login/ouser.ligo/ligo/deploy/sw/pycbc/${ENV_OS}/virtualenv/pycbc-${TRAVIS_TAG}/
      ssh ouser.ligo@oasis-login.opensciencegrid.org osg-oasis-update
    fi
    echo -e "\\n>> [`date`] virtualenv deployment complete"
  fi
fi 

echo -e "\\n>> [`date`] Docker script exiting"

exit 0

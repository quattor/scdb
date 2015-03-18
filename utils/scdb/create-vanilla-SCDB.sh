#!/bin/bash
# This script creates a vanilla SCDB from GitHub site, with both
# SCDB itself and the template library. The cluster examples are then compiled.
#
# Written by Michel Jouvin <jouvin@lal.in2p3.fr>, 30/9/2013
#

git_clone_root=${TMPDIR:-/tmp}/quattor-template-library
scdb_dir=${TMPDIR:-/tmp}/scdb-vanilla
tl_download_script=get-template-library
github_repos_url=https://github.com/quattor
release_tools_repo=release
remove_scdb=0
verbose=0
tl_download_args=""
externals_root_url=https://svn.lal.in2p3.fr/LCG/QWG/External
scdb_external_list="ant panc scdb-ant-utils svnkit"
panc_version=panc-10.1
ant_version=apache-ant-1.9.4
scdb_ant_utils_version=scdb-ant-utils-9.0.2
svnkit_version=svnkit-1.8.6
cluster_groups_default="grid"
cluster_groups=


# scdb source is typically a clone of GitHub scdb repo, switched to the appropriate
# version/branch. By default, the root of the clone is 2 level upper than the directory
# containing this script (util/scdb)
scdb_source="$(dirname $0)/../.."
if [ ! -e "${scdb_source}/quattor.build.xml" ]
then
  echo "$(basename $0) must be run from a scdb repository clone".
  exit 1
fi

usage () {
  echo "usage:  `basename $0` [-F] [--debug] [-d scdb_dir] [options...] [quattor_version]"
  echo ""
  echo "    Valid options are the following ones plus all valid get-template-library options:"
  echo ""
  echo "        -d scdb_dir : directory where to create SCDB."
  echo "                      (D: ${scdb_dir})"
  echo "        --debug : debug mode. Checkout rather than export templates"
  echo "        -F : remove scdb_dir if it already exists."
  echo "        --group : cluster group to compile. Can be specified multiple times (D:${cluster_groups_default})"
  echo ""
  exit 1
}


# Redirect stdout and stderr to /dev/null, except if --debug
silent_command () {
  exec 3>&1 4>&2
  [ ${verbose} -eq 0 ] && exec &>/dev/null
  $*
  status=$?
  exec 1>&3 2>&4
  return $status
}


copy_scdb_external () {
  if [ -z "$1" ]
  then
    echo "Internal error: missing destination directory in copy_scdb_exernal()"
    exit 20
  fi
  if [ -z "$2" ]
  then
    echo "Internal error: missing external version in copy_scdb_exernal()"
    exit 20
  fi
  echo "Adding $1 version $2..."
  svn export ${externals_root_url}/$2 ${scdb_dir}/external/$1 > /dev/null
  if [ $? -ne 0 ]
  then
    echo "Error adding $1. Aborting..."
    exit 21
  fi
}

while [ -n "$(echo $1 | grep '^-')" ]
do
  case $1 in
  --add-legacy)
     add_legacy=1
     ;;

  -d)
    shift
    scdb_dir=$1
    ;;

  --debug)
    # Must be passed to the script used to download the template library
    tl_download_args="${tl_download_args} $1"
    verbose=1
    ;;

  -l)
    list_branches=1
    ;;

  -F)
    remove_scdb=1
    ;;

  --group)
    shift
    cluster_groups="${cluster_groups} $1 "
    ;;

  --help)
    usage
    ;;

  *)
    # All options unknown to this script are assumed to be options of the script used
    # to download the template library... Not ideal but wrong options will raise an 
    # error in this other script.
    tl_download_args="${tl_download_args} $1"
    # If next parameter is not an option but is followed by a non empty parameter, assume
    # it is the option value.
    if [ -z "$(echo $2 | grep '^-')" -a -n "$3" ]
    then
      tl_download_args="${tl_download_args} $2"
      shift
    else
      echo "Invalid option ($1). Aborting..."
      usage
    fi
    ;;
  esac
  shift
done

if [ -n "$1" ]
then
  tl_version=$1
  tl_download_args="${tl_download_args} ${tl_version}"
else
  echo "Quattor version to checkout is required (use 'HEAD' for the most recent revision)"
  exit 1
fi

if [ "${tl_version}" \> "15." -o "${tl_version}" = "HEAD" ]
then
  cluster_groups_enabled=1
  if [ -z "${cluster_groups}" ]
  then
    cluster_groups=${cluster_groups_default}
  fi
else
  cluster_groups_enabled=0
  if [ -n "${cluster_groups}" ]
  then
    echo "WARNING: --group option supported only for version HEAD or >= 15. Ignored."
  fi
  cluster_groups=default      # Informational
fi


# Check (or remove) the SCDB destination directory.
if [ -d ${scdb_dir} ] 
then
  if [ ${remove_scdb} -eq 0 ]
  then
    echo "Directory $scdb_dir already exists. Remove it or use -F"
    exit
  else
    echo "Removing ${scdb_dir}..."
    rm -Rf ${scdb_dir}
  fi
fi
mkdir -p ${scdb_dir}

# Check (or remove+create) if the destination directory for Git clones exists
if [ -d ${git_clone_root} ]
then
  if [ ${remove_scdb} -eq 0 ]
  then
    echo "Directory ${git_clone_root} already exists. Remove it or use -F"
    exit
  else
    echo "Removing ${git_clone_root}..."
    rm -Rf ${git_clone_root}
  fi
fi
mkdir ${git_clone_root}


echo "Creating vanilla SCDB from $scdb_source in $scdb_dir..."
cp -R ${scdb_source}/* ${scdb_dir}
if [ $? -ne 0 ]
then
  echo "Error creating vanilla SCDB. Aborting..."
  exit 1
fi
for external in ${scdb_external_list}
do
  tmp=$(echo ${external} | sed -e 's/-/_/g')
  external_version_variable=${tmp}_version
  copy_scdb_external ${external} ${!external_version_variable}
done


# Download template library
# First download the get-template-library script from GitHub if not present in
# the current directory
if [ -e "$(dirname $0)/${tl_download_script}" ]
then
  tl_download_cmd="$(dirname $0)/${tl_download_script}"
else
  [ $verbose -eq 1 ] && echo "Downloading ${tl_download_script} script..."
  silent_command git clone ${github_repos_url}/${release_tools_repo}.git ${git_clone_root}/${release_tools_repo}
  tl_download_cmd=${git_clone_root}/${release_tools_repo}/src/scripts/${tl_download_script}
fi
echo "Downloading template libary (version: ${tl_version})..."
[ $verbose -eq 1 ] && echo "Executing ${tl_download_cmd} with arguments '${tl_download_args}'"
${tl_download_cmd} -d ${scdb_dir}/cfg ${tl_download_args}
if [ $? -ne 0 ]
then
  echo "Failed to download template libary. Check your options: must be valid for this script or ${tl_download_script}"
  usage
fi


# Create a quattor.build.properties file.
# Enable the use of cluster groups only for version HEAD or a version >= 15.x as 
# before the template-library-examples repo was not configured with cluster groups.
# Version is last parameter of the command line: assume it is valid if template
# library download succeeded.
property_file=${scdb_dir}/quattor.build.properties
echo "Creating ${property_file}..."
cat <<EOF >  ${property_file}
build.annotations=\${basedir}/build.annotations
pan.formats=json,dep
EOF
if [ ${cluster_groups_enabled} -eq 1 ]
then
  cat <<EOF >>  ${property_file}
clusters.groups.enable=true
EOF
fi 


# Compile examples
for group in ${cluster_groups}
do
  echo "Compiling clusters/example (group=${group})..."
  ant_options=""
  if [ ${cluster_groups_enabled} -eq 1 ]
  then
    ant_options="-Dcluster.group=${group}"
  fi
  (cd ${scdb_dir}; external/ant/bin/ant --noconfig ${ant_options})
done

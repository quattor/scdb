#!/bin/sh
#
# This script is now just a wrapper to createPackagesTemplate
#
# Written by Michel Jouvin <jouvin@lal.in2p3.fr>
#
# Copyright (c) 2004 by Michel Jouvin and Le Centre National de
# la Recherche Scientifique (CNRS).  All rights reserved.

# The software was distributed with and is covered by the European
# DataGrid License.  A copy of this license can be found in the included
# LICENSE file.  This license can also be obtained from
# http://www.eu-datagrid.org/license.

usage () {
  echo "Usage: `basename $0` RPM_Directory"
  echo ""
  echo "    RPM_Directory : directory where CA RPMs reside."
  echo ""
  exit 1
}

if [ -z "$1" ]
then
  echo "Error : Missing RPM directory"
  usage
fi

tools_dir=`dirname $0`
createPackagesTemplate=${tools_dir}/../misc/createPackagesTemplate
trusted_cas_ns=security
trusted_cas_template=${tools_dir}/../../../standard/${trusted_cas_ns}/cas.tpl

if [ ! -x ${createPackagesTemplate} ]
then
  echo "Error : ${createPackagesTemplate} not found"
  exit 2
fi

${createPackagesTemplate} --namespace security \
                          --template ${trusted_cas_template} \
                          $1



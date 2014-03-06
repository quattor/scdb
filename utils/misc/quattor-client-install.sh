#!/bin/sh -x
#-----------------------------------------------------------------------------
#
# script to install Quattor client on an already installed machine
# Derived from ks-post-reboot in AII
# MAy need some tuning...
#
# Written by Michel Jouvin <jouvin@lal.in2p3.fr>
#
#-----------------------------------------------------------------------------

fail () {
echo "Quattor installation failed: $1"
exit -1
}


###########################################################################
#
# Install the Quattor client
#
###########################################################################

# Note: The following block (between SPMA-start and SPMA-end) is specific
#       to clients running SPMA. If you want to use APT/YUM instead
#       for managing your clients, you must *remove* the complete block,
#       and replace it with:
#          1. adding the Quattor APT repository to the
#             APT/Yum configuration
#          2. run:
#              'apt-get update && apt-get install quattor-client' (for APT)
#              'yum install quattor-client' (for YUM)
#
#       See the APT/Yum chapter of the Quattor installation guide for
#       details on how to do this.

#--------------------------------------------------------------------------
# SPMA-start
#--------------------------------------------------------------------------
#
# install CCM, NCM, SPMA and friends
#

# Default is SL 4.6 i386
os_version=sl460
os_arch=x86_64

if [ -n "$1" ]
then
  os_version=$1
fi

if [ -n "$2" ]
then
  os_arch=$2
fi

QUATTORSRV=quattorsrv.lal.in2p3.fr
REPOSITORY=http://${QUATTORSRV}/packages/quattor/sl
REPOSITORY_NCM=http://${QUATTORSRV}/packages/ncm-components
REPOSITORY_OS=http://${QUATTORSRV}/packages/os/${os_version}-${os_arch}/base/SL/RPMS
CDBSERVER=${QUATTORSRV}
HOSTNAME=`hostname` 

# Quattor generic libraries and External Packages

/bin/rpm --force -Uvh \
   $REPOSITORY_OS/perl-Compress-Zlib-1.42-1.el4.${os_arch}.rpm	\
   $REPOSITORY/perl-LC-1.0.11-1.noarch.rpm		\
   $REPOSITORY/perl-AppConfig-caf-1.4.10-1.noarch.rpm    \
   $REPOSITORY/perl-CAF-1.4.10-1.noarch.rpm		\
   $REPOSITORY_OS/perl-Crypt-SSLeay-0.51-5.${os_arch}.rpm	\
   $REPOSITORY_OS/perl-Proc-ProcessTable-0.39-1.${os_arch}.rpm \
   $REPOSITORY_OS/perl-DBI-1.40-8.${os_arch}.rpm              \
   #|| fail "rpm failed ($?)"
    
# Configuration Cache Manager

/bin/rpm --force -Uvh \
   $REPOSITORY/ccm-1.5.14-1.noarch.rpm			\
   $REPOSITORY/ncm-template-1.0.9-1.noarch.rpm		\
   #|| fail "rpm failed ($?)"

# Node Configuration Deployer

/bin/rpm --force -Uvh \
   $REPOSITORY/ncm-ncd-1.2.14-1.noarch.rpm		\
   $REPOSITORY/ncm-query-1.1.0-1.noarch.rpm		\
   #|| fail "rpm failed ($?)"

# Software Package Management Agent

/bin/rpm --force -Uvh \
   $REPOSITORY/rpmt-py-1.0.0-1.noarch.rpm		\
   $REPOSITORY/spma-1.10.22-1.noarch.rpm			\
   $REPOSITORY_NCM/ncm-spma-1.4.5-1.noarch.rpm		\
   #|| fail "rpm failed ($?)"

# CDP listend daemon

/bin/rpm --force -Uvh \
   $REPOSITORY/cdp-listend-1.0.17-1.noarch.rpm		\
   #|| fail "rpm failed ($?)"

# Configuration Dispatch Daemon

/bin/rpm --force -Uvh \
   $REPOSITORY/ncm-cdispd-1.1.11-1.noarch.rpm		\
   #|| fail "rpm failed ($?)"

#
# At this point, the Kernel must be upgraded (see Savannah #5007)
#

##/bin/rpm --force -ivh $REPOSITORY/kernel-2.4.21-32.0.1.EL.athlon.rpm
#
#
#--------------------------------------------------------------------------
# SPMA-end
#--------------------------------------------------------------------------


###########################################################################
#
# Configure the Quattor client
#
###########################################################################


# Create the initial CCM configuration file

cat <<End_Of_CCM_Conf > /etc/ccm.conf
profile			http://$CDBSERVER/profiles/$HOSTNAME.xml
End_Of_CCM_Conf

# initialise the CCM

/usr/sbin/ccm-initialise \
    || fail "CCM intialization failed ($?)"

# Download my configuration profile

/usr/sbin/ccm-fetch || fail "ccm-fetch failed ($?)"

# Upgrade the system

/usr/sbin/ncm-ncd --configure spma \
    || fail "/usr/sbin/ncm-ncd --configure spma failed"
/usr/bin/spma --userpkgs=no --userprio=no \
    || fail "/usr/bin/spma failed"
/usr/sbin/ncm-ncd --configure --all

#
exit 0

# end of post reboot script
#-----------------------------------------------------------------------------

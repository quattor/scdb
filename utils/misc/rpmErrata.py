#!/usr/bin/python
# -*- coding: utf-8 -*-
#
# Copyright 2006-2014 CNRS. All rights reserved.
#
# Written by Michel Jouvin <jouvin@lal.in2p3.fr> - 16/7/06
# Python version by Jerome Pansanel <jerome.pansanel@iphc.cnrs.fr> - 19/10/2011

"""rpmErrata - A script for generating Quattor Errata templates

The rpmErrata script generates a template with one 'pkg_ronly' for each RPM
present in the specified directory.
Only the most recent version is inserted into the template.
"""

import os
import sys
import rpm
import optparse
import time
from operator import itemgetter

archList = ['noarch','i386','i586','i686','x86_64']

def compareRPMVersion(x,y):
    if cmp(x[0],y[0]) == 0:
#        print x[3] + ":" + y[3]
        return cmp(x[3],y[3])
    return cmp(x[0],y[0])

_version = "1.1"

versionString = "rpmErrata -- A script for generating Quattor RPM Errata templates (v%s)\n" % (_version)

def rpmCompareVersion(first_version,second_version):
    """This function compares two RPM version numbers.

    Each argument is a list of three variables [epoch,version,release].

    The function returns:
    * 1 if first_version is considered greater than second_version
    * 0 if the both version are equal
    * -1 if first_version is considered less than second_version
    """
    return rpm.labelCompare(first_version,second_version)

def main():
    program = os.path.basename(sys.argv[0])
    usage = "[-h] [-V] [-n DATE] rpm_directory\n\n" \
           + "STDOUT must be redirected to produce the template. It is recommended to\n" \
           + "redirect STDERR to another file as it can produce a lot of output.\n"
    parser = optparse.OptionParser(usage=usage)
    parser.add_option('-V', '--version',
                      help='show version',
                      action='store_true', dest='version', default=False)
    parser.add_option('-n', '--not-after',
                      help='Restrict the template to RPMs with a build time older than DATE',
                      dest='notAfterDate',
                      metavar="DATE")
    (options, args) = parser.parse_args(sys.argv)

    if options.version:
        sys.stdout.write(versionString)
        sys.exit(0)

    elif len(args) != 2:
        sys.stderr.write("usage: %s %s\n" % (program, usage))
        sys.exit(1)

    repository = args[1]

    # Check if the notAfterDate variable is valid
    if options.notAfterDate:
        notAfterDate = options.notAfterDate.split('-')
        if len(notAfterDate) != 3:
            sys.stderr.write("Error: the date (%s) has not a valid format. Please use the following format: YYYY-MM-DD.\n" % (options.notAfterDate))
            sys.exit(1)
        try:
            notAfterTime = time.mktime((int(notAfterDate[0]),int(notAfterDate[1]),int(notAfterDate[2]),0,0,0,0,0,0))
        except:
            sys.stderr.write("Error: the date (%s) is not a valid date. Please use the following date format: YYYY-MM-DD.\n" % (options.notAfterDate))
            sys.exit(1)
    else:
        notAfterTime = None

    if not os.path.isdir(repository):
        sys.stderr.write("Error: No such directory: %s\n" % (repository))
        sys.exit(1)

    fileList = os.listdir(repository)
 
    rpmVersionDict = {}
 
    transactionSet =  rpm.TransactionSet()
    transactionSet.setVSFlags(rpm._RPMVSF_NOSIGNATURES) 
    sys.stdout.write("# Template to add errata RPMs to base configuration\n\n")
    sys.stdout.write("template rpms/errata;\n\n")
 
    # Process each rpm present in the repository
    for filename in fileList:
        if filename[-4:] == '.rpm':
            sys.stderr.write("Processing %s... " % (filename))
            fileObject = os.open(repository + os.path.sep + filename, os.O_RDONLY)
            rpmHeader = transactionSet.hdrFromFdno(fileObject)
            rpmInfo = rpmHeader.sprintf('%{name},%{version},%{release},%{arch}').split(',')
            rpmBuildTime = rpmHeader.sprintf('%{buildtime}')
            arch = archList.index(rpmInfo[3])
            os.close(fileObject)
            internalName = "%s-%s-%s.%s.rpm" % (rpmInfo[0],rpmInfo[1],rpmInfo[2],rpmInfo[3])
            rpmInfo = (rpmInfo[0],rpmInfo[1],rpmInfo[2],arch)
            rpmKey = "%s-%s" % (rpmInfo[0],rpmInfo[3])
            if internalName != filename:
                sys.stderr.write("RPM %s internal name (%s) doesn't match RPM file name. Skipped.\n" % (filename,internalName))
            else:
                if notAfterTime:
                    # Do not include the RPM if its build time is newer than the specified date.
                    if int(rpmBuildTime) > int(notAfterTime):
                        sys.stderr.write("RPM %s is newer than the specified date (%s). Skipped.\n" % (filename, options.notAfterDate))
                        continue
                if not rpmVersionDict.has_key(rpmKey) or (rpmCompareVersion(rpmInfo[0:3],rpmVersionDict[rpmKey][0:3]) > 0):
                    sys.stderr.write("added (replacing older versions)\n")
                    rpmVersionDict[rpmKey] = rpmInfo
                else:
                    sys.stderr.write("skipped (newer version present)\n")

    # Add an entry for the most recent version of every RPM, except kernel.
    # Kernel version is defined explicitly in node configuration and must
    # not be based on the last one available.
    # Kernel modules are added for all possible kernel versions. This is not
    # a problem as their name contains the kernel version used and
    # will not match an already installed RPM if the kernel version used is not
    # matching.
    for (key,rpmInfo) in sorted(rpmVersionDict.items(),key = itemgetter(1),cmp=compareRPMVersion):
        if rpmInfo[0][0:6] == 'kernel' and rpmInfo[0][0:13] != 'kernel-module':
            sys.stderr.write("Adding commented-out entry for kernel %s version %s-%s arch %s\n" % (rpmInfo[0],rpmInfo[1],rpmInfo[2],archList[rpmInfo[3]]))
            sys.stdout.write("#'/software/packages'=pkg_ronly('%s','%s-%s','%s','multi');\n" % (rpmInfo[0],rpmInfo[1],rpmInfo[2],archList[rpmInfo[3]]))
        else:
            sys.stderr.write("Adding entry for %s version %s-%s arch %s\n" % (rpmInfo[0],rpmInfo[1],rpmInfo[2],archList[rpmInfo[3]]))
            sys.stdout.write("'/software/packages'=pkg_ronly('%s','%s-%s','%s');\n" % (rpmInfo[0],rpmInfo[1],rpmInfo[2],archList[rpmInfo[3]]))

if __name__ == '__main__':
    main()

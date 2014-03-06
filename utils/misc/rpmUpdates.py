#!/usr/bin/python
# -*- coding: utf-8 -*-
#
# Copyright 2006-2011 CNRS. All rights reserved.
#
# Written by Michel Jouvin <jouvin@lal.in2p3.fr> - 16/7/06
# Python version by Jerome Pansanel <jerome.pansanel@iphc.cnrs.fr> - 19/10/2011

"""rpmUpdates - A script for generating Quattor Update templates

The rpmUpdates script generates a template with one 'pkg_ronly' for each RPM
present in the specified directory. Optionaly, this script can download the
update RPMs from a specified location.
Only the most recent version is inserted into the template.

Common sources of RPM are :
 * gLite 3.2 updates: http://glitesoft.cern.ch/EGEE/gLite/R3.2/glite-GENERIC/sl5/x86_64/RPMS.updates/
 * UMD 1.0: http://repository.egi.eu/sw/production/umd/1/sl5/x86_64/updates/
"""

import os
import sys
import rpm
import optparse
import urllib
import re
import time

_version = "1.0"

versionString = "rpmUpdates -- A script for generating Quattor RPM Update templates (v%s)\n" % (_version)

def rpmCompareVersion(first_version,second_version):
    """This function compares two RPM version numbers.

    Each argument is a list of three variables [epoch,version,release].

    The function returns:
    * 1 if first_version is considered greater than second_version
    * 0 if the both version are equal
    * -1 if first_version is considered less than second_version
    """
    return rpm.labelCompare(first_version,second_version)

def getRPMList(url):
    rpmList = []
    try:
        indexFile = urllib.urlopen(url)
        rpmRegExp = re.compile('href="([^"]*.rpm)"')
        data = indexFile.read()
        for rpm in rpmRegExp.findall(data):
            if not rpm in rpmList:
                rpmList.append(rpm)
    except:
        sys.stderr.write("Error: Unexpected error when retrieving the RPM list: %s\n" % (sys.exc_info()[0]))
        sys.exit(1)
    return rpmList

def main():
    program = os.path.basename(sys.argv[0])
    usage = "[-h] [-V] [-u URL] [-n DATE] rpm_directory\n\n" \
           + "STDOUT must be redirected to produce the template. It is recommended to\n" \
           + "redirect STDERR to another file as it can produce a lot of output, especially\n" \
           + "if downloading is done at the same time."
    parser = optparse.OptionParser(usage=usage)
    parser.add_option('-V', '--version',
                      help='show version',
                      action='store_true', dest='version', default=False)
    parser.add_option('-u', '--url',
                      help='download RPM from a repository',
                      dest='repository_url',
                      metavar="URL")
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

    if not os.path.isdir(repository):
        sys.stderr.write("Error: No such directory: %s\n" % (repository))
        sys.exit(1)

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

    # Update RPM in repository if an URL is provided
    if options.repository_url:
        if not os.access(repository, os.W_OK):
            sys.stderr.write("Error: The %s directory is not writable.\n" % repository)
            sys.exit(1)
        sys.stderr.write("Loading new RPMs from %s (may take a while)...\n" % (options.repository_url))
        rpmList = getRPMList(options.repository_url)
        if not rpmList:
            sys.stderr.write("Error: the %s url does not contain a list of RPM\n" % (options.repository_url))
            sys.exit(1)
        sys.stderr.write("%i RPM packages to download\n" % len(rpmList))
        for i in range(0,len(rpmList)):
            sys.stderr.write("[%i] Fetching %s ...\n" % (i+1,rpmList[i]))
            inputURL = options.repository_url + '/' + rpmList[i]
            outputURL = repository + '/' + rpmList[i]
            urllib.urlretrieve(inputURL,outputURL)

    fileList = os.listdir(repository)
 
    rpmVersionDict = {}
 
    transactionSet =  rpm.TransactionSet()
    transactionSet.setVSFlags(rpm._RPMVSF_NOSIGNATURES) 
    sys.stdout.write("# Template to add update RPMs to base configuration\n\n")
    sys.stdout.write("template updates/rpms;\n\n")
 
    # Process each rpm present in the repository
    for filename in fileList:
        if filename[-4:] == '.rpm':
            sys.stderr.write("Processing %s... " % (filename))
            fileObject = os.open(repository + os.path.sep + filename, os.O_RDONLY)
            rpmHeader = transactionSet.hdrFromFdno(fileObject)
            rpmInfo = rpmHeader.sprintf('%{name},%{version},%{release},%{arch}').split(',')
            rpmBuildTime = rpmHeader.sprintf('%{buildtime}')
            os.close(fileObject)
            internalName = "%s-%s-%s.%s.rpm" % (rpmInfo[0],rpmInfo[1],rpmInfo[2],rpmInfo[3])
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

    # Add an entry for the most recent version of every RPM.
    for (key,rpmInfo) in rpmVersionDict.items():
        sys.stderr.write("Adding entry for %s version %s-%s arch %s\n" % (rpmInfo[0],rpmInfo[1],rpmInfo[2],rpmInfo[3]))
        sys.stdout.write("'/software/packages'=pkg_ronly('%s','%s-%s','%s');\n" % (rpmInfo[0],rpmInfo[1],rpmInfo[2],rpmInfo[3]))

if __name__ == '__main__':
    main()

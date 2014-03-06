#!/usr/bin/perl

# Copyright (c) 2004 by Charles A. Loomis, Jr. and Le Centre National de
# la Recherche Scientifique (CNRS).  All rights reserved.

# The software was distributed with and is covered by the European
# DataGrid License.  A copy of this license can be found in the included
# LICENSE file.  This license can also be obtained from
# http://www.eu-datagrid.org/license.

use strict;

# Check that at least some directories were given. 
if ($#ARGV<0) {
    info();
    exit(1);
}

# Collect all of the RPMs. 
my $error = 0;
my @rpms = ();
foreach my $dir (@ARGV) {

    # Is it really a directory? 
    unless (-d $dir) {
	print STDERR "$dir is not a directory\n";
	$error = 1;
    }

    # Open it up and collect all rpms. 
    opendir DIR, $dir;
    my @files = grep /\.rpm$/, map "$dir/$_", readdir DIR;

    # Push each onto the list.
    foreach my $file (@files) {
	push @rpms, $file;
    }
}

# Don't do anything if there was an error. 
exit(1) if ($error);

# Now loop over all of the RPMs.
my $rpm;
foreach $rpm (@rpms) {

    # Get the true (or at least the embedded) name of the RPM. 
    my $rpmname = `rpm -qp --queryformat '%{name} \| %{arch}\n' $rpm 2>/dev/null`;
    chomp($rpmname);

    # Collect the explict "provides" information. 
    open IN, "rpm -qp --provides $rpm 2>/dev/null |";
    while (<IN>) {
	chomp;
	m%^\s*(\S+)(\s+.*)?%;
	print "$1 | $rpmname\n";
    }
    close IN;

    # Also collect the executables in the various (s)bin areas as
    # these also show up in RPM requirements as well. 
    open IN, "rpm -qpl $rpm 2>/dev/null |";
    while (<IN>) {
	chomp;
	print "$_ | $rpmname\n" if (m%^/(usr/)?(s)?bin/%);
    }
    close IN;
}

exit;

# Print out information on how to use this script. 
sub info {

    print << "EOF"

This script takes a list of directories (which contain RPMs) and
extracts the "provides" information from those RPMs.  The information
is written to the standard output in a format appropriate for the
./rpmRequires.pl script.  The output should be piped to a file. 

The script extracts the necessary information via the rpm command.
Consequently, this must be available from the standard PATH.
Extracting the necessary information may take some time for a large
number of RPMs.

Usage:

./rpmProvides.pl <directory> [<directories...>]

Giving no arguments prints this help message.

EOF
; 

}



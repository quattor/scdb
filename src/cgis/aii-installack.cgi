#!/usr/bin/perl -w

#
# aii-installack
#
# Copyright (c) 2003 EU DataGrid.
# For license conditions see http://www.eu-datagrid.org/license.html
#
# When a client node finish to install itself, it should send a
# notification message to the AII server. In this way, the AII server
# can mark the node to boot from its local hard disk the next time it reboots.
# If the client fails to send the notification message, it will get
# reinstalled during the next reboot.
#
# Enrico Ferro <enrico.ferro@pd.infn.it>
# Rafael Garcia Leiva <angel.leiva@uam.es>
#

use strict;
use Socket;

#
# Beginning sequence for EDG initialization
#
BEGIN {
    # use perl libs in /usr/lib/perl
    unshift(@INC, '/usr/lib/perl');
    unshift(@INC,'/opt/edg/lib/perl');
}

print "Content-type: text/plain\n\n";

#
# Check if the web server returned client address
#
if (!defined ($ENV{REMOTE_ADDR})) {
    print "[ERROR] aii-installack: hostname not defined\n";
    exit 0;
}

#
# Try to get client address
#
my $packed_address = pack('C4', split(/\./ ,$ENV{REMOTE_ADDR}));
my $host = gethostbyaddr($packed_address, AF_INET);

if ($host eq '') {
    print "[ERROR] aii-installack: invalid hostname ($ENV{REMOTE_ADDR})\n";
    exit 0;
}

#
# Run shellfe via sudo
#
my $command = "/usr/bin/sudo /usr/sbin/aii-shellfe " .
              "--boot $host --nodhcp --noosinstall";
if (system ($command)) {
    print "[ERROR] aii-installack: error while executing command: $command\n";
} else {
    print "[INFO] aii-installack: host '$host' configured " .
          "to boot from local disk\n";
}


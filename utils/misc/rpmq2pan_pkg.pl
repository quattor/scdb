#!/usr/bin/perl -w
#
# Copyright (c) 2005 by Marco E. Poleggi, and the European Organization for
# Nuclear Research (CERN).  All rights reserved.
#
# The software was distributed with and is covered by the European
# DataGrid License.  A copy of this license can be found in the included
# LICENSE file.  This license can also be obtained from
# http://www.eu-datagrid.org/license.
#
# rpmq2pan_pkg: rpm query to Pan package list template converter.
# Query the RPM database for all the installed packages and write a Pan template
# holding the corresponding package list, formatted either as
#    "/software/packages" = pkg_add("mypkg1","0.1.2-3","i386")
#        (for "standard" 'pro_software_packages_<platform>' templates) or
#    "_defpkg",list("0.1.2-3","i386")
#        (for "defaults" 'pro_software_packages_defaults_<platform>' templates).
# Multiple versions of the same package are also handled. For 'default'
# templates, ask which to keep; for 'standard' templates, keep all versions.
# See the usage() functions for details about the program arguments.


################################################################################
# uses and globals

use Getopt::Long;

my %pkgs = ();
my @pkg_list = ();
my $rpm_qcmd = 'rpm -qa --queryformat';
my $rpm_qfmt = '\'[%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n]\'';
my $dbg = '';

################################################################################
# functions

# usage: obvious.
sub usage {
    print(<<EOF
Usage: $0 [OPTIONS]

Quattor utility. Query the local RPM database for all the installed packages
and write a Pan template holding the corresponding package list. The
output template format and name can be controlled through specific options; two
basic types can be generated:
    'OPREFIX_PNAME.tpl'             ("standard" templates)
    'OPREFIX_defaults_PNAME.tpl'    ("defaults" templates)
(see also the 'pan-templates' package).

Mandatory arguments to long options are mandatory for short options too.
-d, --deftpl    output a "defaults" software package template. The default is
                off, that is to produce a "standard" template.
-h, --help      display this help and exit.
-i, --incdef    when generating a standard template, add a line:
                'include OPREFIX_defaults_PNAME;'. Default is off.
-m, --minspec   when generating a standard template, write only the package name
                specification. However, *multiple* package versions will
                always have full specifications. Default is off.
-o, --outprfx=OPREFIX   use OPREFIX as the initial part of the output template
                name. The default is 'pro_software_packages'.
-p, --platform=PNAME    use PNAME as the suffix part of the output template
                name. The default is 'UNDEF'.
EOF
    );
}


################################################################################
# MAIN

# Option setup.
my $deftpl = '';
my $incdef = '';
my $help = '';
my $minspec = '';
my $outprfx = 'pro_software_packages';
my $platform = 'UNDEF';

unless(&GetOptions( "deftpl"    => \$deftpl,
                    "help"      => \$help,
                    "incdef"    => \$incdef,
                    "minspec"   => \$minspec,
                    "outprfx=s" => \$outprfx,
                    "platform=s"=> \$platform)) {
    print(STDERR "Error parsing the command line.\n");
    exit(1);
}

if($help) {
    usage();
    exit;
}

if($minspec or $incdef) {
    if($deftpl) {
        print(STDERR "Options --incdef/--minspec are not compatible with --deftpl.\nType $0 -h for help.\n");
        exit;
    }
}

# open a pipe to get rpm list
my $rpmcmd = "$rpm_qcmd $rpm_qfmt";
print("Executing: $rpmcmd\n");
open(RPM, "$rpmcmd|") or die("Unable to pipe from rpm: $!");

# get the rpm ouput: build a hash whose values hold lists of pairs, such as
#   <#pairs>:<ver1> <arch1>:<ver2> <arch2>...
while(<RPM>) {
    chomp;
    my ($name, $ver, $arch) = split(/ /);
    $pkgs{$name}[0]++;
    push(@{$pkgs{$name}}, join(' ', $ver, $arch));
    print(STDERR "pkgs{$name}: @{$pkgs{$name}}\n") if($dbg);
}

# walk through the hash and build a formatted package list
for $name (sort(keys(%pkgs))) {
    if($pkgs{$name}[0] < 1) {
        die("Invalid reference number for pkg name <$name>");
    }
    elsif($pkgs{$name}[0] == 1) {
        # single version
        my ($ver, $arch) = split(' ', $pkgs{$name}[1]);
        if($deftpl) {
            push(@pkg_list, "\"_$name\",list(\"$ver\",\"$arch\"),\n");
        }
        else {
            $minspec ?
                push(@pkg_list, "\"/software/packages\" = pkg_add(\"$name\");\n")
                :
                push(@pkg_list, "\"/software/packages\" = pkg_add(\"$name\",\"$ver\",\"$arch\");\n");
        }
    }
    else {
        # more than one version found
        if($deftpl) {
            # ask which version to keep
            print("Choose a version for package <$name>\n");
            for(1..$#{$pkgs{$name}}) {
                print("$_: $pkgs{$name}[$_]\n");
            }
            print(": ");
            while(<>) {
                chomp;
                if(/^\d+$/ and 1<=$_ and $_<=$#{$pkgs{$name}}) {
                    my ($ver, $arch) = split(' ', $pkgs{$name}[$_]);
                    push(@pkg_list, "\"_$name\",list(\"$ver\",\"$arch\"),\n");
                    last;
                }
                print("Invalid choice. Retry: ");
            }
        }
        else {
            # keep all versions
            for(@{$pkgs{$name}}[1, -1]) {
                my ($ver, $arch) = split(' ');
                push(@pkg_list, "\"/software/packages\" = pkg_add(\"$name\",\"$ver\",\"$arch\",\"multi\");\n");
            }
        }
    }
}


# Print out the file
my $date = localtime();
my $tpl_name = $outprfx.'_';
if($deftpl) {
    $tpl_name .= "defaults_$platform";
    open(OUT, ">$tpl_name.tpl")
        or die("Unable to create output file: $!");
    print(OUT <<EOF
#
# PAN default packages template for $platform
# Generated by $0 on $date.
#
template $tpl_name;

define variable package_default = nlist(
 @pkg_list);
EOF
    );
}
else {
    $tpl_name .= "$platform";
    open(OUT, ">$tpl_name.tpl")
        or die("Unable to create output file: $!");
    print(OUT <<EOF
#
# PAN packages template for $platform
# Generated by $0 on $date.
#
template $tpl_name;

EOF
    );
    if($incdef) {
        print(OUT
"include ${outprfx}_defaults_$platform;\n\n");
    }
    print(OUT
" @pkg_list");
}

close OUT;
print("Template $tpl_name.tpl written.\n");

exit;

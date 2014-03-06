#!/usr/bin/perl

# Copyright (c) 2004 by Charles A. Loomis, Jr. and Le Centre National de
# la Recherche Scientifique (CNRS).  All rights reserved.

# The software was distributed with and is covered by the European
# DataGrid License.  A copy of this license can be found in the included
# LICENSE file.  This license can also be obtained from
# http://www.eu-datagrid.org/license.

use strict;
use Getopt::Long;


my $ignore_missing_dep = 0;
my $verbose = 0;
my $warn_duplicates = 0;

# Defines available kernel variants in the OS distribution
# Kernel variant RPMs are considered the same for dependency management
# (will be handled at PAN level). Default should be appropriate.
my $kernel_variants = 'smp|largesmp|hugemem|xenU|debug|xen';


# Process the script arguments

my %options = ();
&GetOptions(\%options, "help", 
                       "ignore-missing",
                       "kernel-variants=s",
                       "warn-duplicates",
                       "verbose") or info();


if ( defined($options{help}) ) {
  info();
}

if ( defined($options{'ignore-missing'}) ) {
  $ignore_missing_dep = 1;
}

if ( defined($options{'kernel-variants'}) ) {
  $kernel_variants = $options{'kernel-variants'};
}

if ( defined($options{'verbose'}) ) {
  $verbose = 1;
}

if ( defined($options{'warn-duplicates'}) ) {
  $warn_duplicates = 1;
}

# There must be at least the file containing the provides database and
# at least one directory.
if ( $#ARGV < 1 ) {
  info();
}

# Check all is well with the DB file.
my $providedb = shift(@ARGV);
if ( !-f $providedb ) {
  print STDERR "First argument must be provides DB file.\n";
  info();
  exit(1);
}


# Read in the feature database, as produced by rpmProvides.pl, and put into hash.
# Kernel and kernel related RPMs/features are handled specifically to ensure that
# there is only one entry in the requirements database, whatever is the architecture
# when several are supported in the same distribution (like i686,/athlon in SL3) or
# the kernel variant (smp, largesmp...).

my %provides;
my $distrib_arch;
my $kernel_default_arch;
my $compat_arch = undef;
my $compat_kernel_arch = undef;
my $java_arch;
my %kernel_archs;
open IN, "<$providedb";
while (<IN>) {
  chomp;
  m%^\s*(\S+)\s*\|\s*(\S+)\s*\|\s*(\S+)\s*$%;
  my $feature = normalizeRpmName($1,'feature');
  my $rpmname = normalizeRpmName($2);
  my $rpmarch = $3;

  if ( $warn_duplicates &&
       defined($provides{$feature} ) && 
       ( $provides{$feature}->{rpm} ne $rpmname ) ) {
    print STDERR "WARNING : Duplicate provides for $feature with different value:\n";
    print STDERR "          Existing value: $provides{$feature}->{rpm}\n";
    print STDERR "          New value:      $rpmname\n\n";
  }
  $provides{$feature}->{rpm} = $rpmname;

  $provides{$feature}->{archs}->{$rpmarch} = 1;

  # Guess kernel architecture in case it is different from distribution architecture,
  # e.g. i686. If there are several kernel archs, use one as the default one.
  if ( ( $feature eq "kernel" ) && ( $rpmname eq "kernel" ) ) {
    $kernel_archs{$rpmarch} = 1;
    if ( $rpmarch eq "i686" ) {
      $distrib_arch = "i386";
      $kernel_default_arch = $rpmarch;
    } else {
      $distrib_arch = $rpmarch;
      unless ( defined($kernel_default_arch) ) {
        $kernel_default_arch = $rpmarch;
      }
      unless ( defined($compat_arch) || ($distrib_arch ne 'x86_64') ) {
        $compat_arch = 'i386';
        # Required to find ix86 version of glibc
        $compat_kernel_arch = 'i686'
      }
    }
  # Guess java architecture : if several found, prefer arch matching 
  # distribution architecture
  } elsif ( $feature =~ /^j(2s)?dk/ ) {
    if ( !defined($java_arch) ) {
      $java_arch = $rpmarch;
    } elsif ( $java_arch ne $distrib_arch ) {
      $java_arch = $rpmarch;
    }
  }

}
close IN;

# Collect all of the RPMs.
my $error = 0;
my @rpms  = ();
foreach my $dir (@ARGV) {

  # Is it really a directory?
  unless ( -d $dir ) {
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

# Collect all of the packages with their dependencies.
# Duplicates packages are removed from the output file if architecture matches.
# Most of the duplicates come from kernel related RPM name normalization.
# Conversely, nothing specific is done with duplicated dependencies : this will
# be handled by the XSL stylesheet.
my %all;

# Loop over each rpm generating the package dependency information.
print "<pkgs>\n";
foreach my $rpm (@rpms) {

  # Get info from the RPM.
  my $rpminfo = `rpm -qp --queryformat '%{name} %{version} %{release} %{arch}\n' $rpm 2>/dev/null`;
  chomp($rpminfo);
  my ( $rpmname, $rpmver, $rpmrel, $rpmarch ) = split '\s+', $rpminfo;
  $rpmname = normalizeRpmName($rpmname);
  $rpmarch = normalizeRpmArch($rpmname,$rpmarch);

  unless ( defined($all{$rpmname}) && ($all{$rpmname} eq $rpmarch) ) {
    $all{$rpmname} = $rpmarch;

    # Generate the dependency information for this RPM.
    # For each dependency, search the RPM providing the dependency
    # (as indicated by %provides) with the appropriate arch match.
    my %deps;
    open IN, "rpm -qp --requires $rpm 2>/dev/null |";
    while (<IN>) {
      chomp;
      m%^\s*(\S+)(\s+.*)?%;
      if ( defined( $provides{$1} ) && ( $provides{$1}->{rpm} ne $rpmname ) ) {
        my $deparch = undef;
        my @arch_candidates;
  
        # If rpmarch=distrib_arch, be sure to search for kernel_default_arch first
        # Also add kernel_default_arch if current RPM is noarch (some noarch RPMs
        # are hooks for kernel modules)
        if ( ($rpmarch eq $distrib_arch) || ($rpmarch eq 'noarch') ) {
          push @arch_candidates, $kernel_default_arch;
        }
        # If rpmarch=compat_arch, search for compat_kernel_arch too.
        # If rpmarch=compat_kern_arch, search for compat_arch too.
        if ( ($rpmarch eq $compat_arch) && defined($compat_kernel_arch) ) {
          push @arch_candidates, $compat_kernel_arch;
        }
        if ( ($rpmarch eq $compat_kernel_arch) && defined($compat_arch) ) {
          push @arch_candidates, $compat_arch;
        }

        # Add same arch as the processed RPM (covers noarch and compatibility arch)
        push @arch_candidates, $rpmarch;

        # If rpmarch=kernel_default_arch, look also for distrib_arch
        push @arch_candidates, $distrib_arch if $rpmarch eq $kernel_default_arch;

        # Next add distribution arch if not the same as the currently processed RPM
        push @arch_candidates, $distrib_arch if $rpmarch ne $distrib_arch;

        # Add Java architecture if different from distrubtion architecture
        if ( defined($java_arch) && ($java_arch ne $distrib_arch) ) {
          push @arch_candidates, $java_arch;
        }

        # And last, add noarch (should not conflict with anything else
        push @arch_candidates, "noarch" if $rpmarch ne "noarch";

        foreach my $arch (@arch_candidates) {
          if ( defined( $provides{$1}->{archs}->{$arch} ) ) {
            $deparch = $arch;
            last;
          }
        }
        unless ( defined($deparch) ) {
          print STDERR "WARNING : No valid arch found for $rpmname ($rpmarch) dependency $1\n";
          print STDERR "          Available archs for $1 : " . join(',', keys(%{$provides{$1}->{archs}})) . "\n";
          unless ($ignore_missing_dep) {
            print STDERR "Use option -i to ignore missing dependencies.\n";
            exit(2);
          }
        }
        $deps{ $provides{$1}->{rpm} } = $deparch;
      }
    }
    close IN;
  
    # Generate the entry in the XML file.
    my $value = "  <pkg>\n"
      . "    <id>$rpmname</id>\n"
      . "    <version>$rpmver-$rpmrel</version>\n"
      . "    <arch>$rpmarch</arch>\n";
    foreach ( sort keys %deps ) {
      $value .= "    <dep><rpm>$_</rpm><arch>$deps{$_}</arch></dep>\n";
    }
    $value .= "  </pkg>\n";
  
    # Save it.
    print $value;

  # Duplicated package : probably a kernel related package...
  } else {
    if ( $verbose ) {
      print STDERR "Duplicated package entry ignored ($rpmname, $rpmarch)\n";
    }
  }
}

# Generate distribution architecture entry

if ( $distrib_arch && $kernel_default_arch ) {
  my $value = "  <arch>\n";
  $value .= "    <distrib>$distrib_arch</distrib>\n";
  $value .= "    <kernel>$kernel_default_arch</kernel>\n";
  $value .= "    <compat>$compat_arch</compat>\n" if defined($compat_arch);
  $value .= "    <compat-kernel>$compat_kernel_arch</compat-kernel>\n" if defined($compat_kernel_arch);
  $value .= "    <java>$java_arch</java>\n" if defined($java_arch);
  $value .= "  </arch>\n";
  print $value;
} else {
  print STDERR "Unable to determine distribution and kernel architectures";
  exit 7;
}

print "</pkgs>\n";

exit;


# Function to normalize kernel and kernel modules RPM/feature names to the name
# without kernel variants.
# Kernel variant is appended to the RPM name, except for kernels where there is '-'
# between  'kernel' and variant.

sub normalizeRpmName ($:$) {
  my $name = shift;
  my $nameCategory = 'RPM';
  if ( length(@_) > 0 ) {
    $nameCategory = shift;
  }
  
  if ($name =~ m%^(kernel)(-[\w\-\.]*?)?($kernel_variants)$% ) {
    my $newname = $1;
    # If length($2)=1, means it is a '-' separating 'kernel' from its variant.
    if ( length($2) > 1 ) {
      $newname .= $2;
    }
    if ( $verbose ) {
      print STDERR "Kernel related $nameCategory name $name changed to $newname\n";
    }
    $name = $newname;
  }
  
  return($name);
}


# Function to normalize kernel and kernel modules RPM/feature architecture
# to the main distribution architecture. Use to avoid multiple entries
# with different architectures in requirements database for distribution
# supporting several architectures (like i686/athlon in SL3).
# Kernel architecture variants are handled by PAN templates.

sub normalizeRpmArch ($$) {
  my ($name, $arch) = @_;

  if ( ($name =~ m%^kernel$%) && defined($kernel_archs{$arch}) ) {
    if ( $verbose ) {
      print STDERR "Kernel related RPM architecture changed from $arch to $kernel_default_arch\n"; }
    $arch = $kernel_default_arch;
  }

  return($arch);
}


# Print out information on how to use this script.
sub info {

  print << "EOF"

This script takes a file generated from the rpmProvides.pl script
containing the package dependency information and a list of
directories containing RPMs.  It generates an XML file suitable 
for use with the comps.xsl stylesheet.   

The script extracts the necessary information via the rpm command.
Consequently, this must be available from the standard PATH.
Extracting the necessary information may take some time for a large
number of RPMs.

Usage:

./rpmRequires.pl [--ignore-missing] \
                 [--kernel-variants=<variants_regexp>]
                 [--warn-duplicates] \
                 [--verbose] \ 
                 <provides DB file> <directory> [<directories...>]

    --ignore-missing (-i) : don't consider missing dependencies as
                            an error. Just ignore them.
    --kernel-variants : regexp matching kernel variants available in
                        the distribution.
    --verbose : very verbose output.
    --warn-duplicates : issue a warning is a feature is provided
                        by several different RPMs.

Giving no arguments prints this help message.

IMPORTANT NOTE: Duplicates (files provided by 2 different packages)are
    not output from this script.  It is the responsibility of the 
    consumer to do something sensible with these duplicates (often they
    can be ignored).

EOF
    ;
exit (1);
}

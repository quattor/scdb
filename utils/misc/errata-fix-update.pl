#!/usr/bin/perl

# This script will update errata-fix pkg_repl versions to those found on errata templates
# This will surely break something, so ckeckdeps verifications are in order before deploying

use strict;
use warnings;

my $OS_LIST = 'sl450-x86_64 sl460-i386 sl460-x86_64 sl470-i386 sl470-x86_64 sl520-x86_64 sl530-x86_64 sl540-x86_64 sl550-x86_64';

my $DATE;
if ( scalar(@ARGV) > 0 ) {
  $DATE = $ARGV[0];
} else {
  $DATE = qx{date +%Y%m%d};
}
chomp $DATE;

# Verify current working directory
if ( ! -d "cfg/sites/grif/repository" ) {
  die "ERROR: this should be run from the base dir";
}

foreach my $OS (split(/ /, $OS_LIST)) {
  my $tmpFile = '/tmp/delete_this-errata-fix.tmp';
  my $file = "cfg/os/$OS/rpms/errata/$DATE-fix.tpl";
  my $errata = "cfg/os/$OS/rpms/errata/$DATE.tpl";
  my $defaultarch = (split(/-/, $OS))[1];
  if ( -f $file && -f $errata ) {
    print "Updating: $file\n";
    my $changed = 0;
    open my $input, '<', $file or die "can't open $file: $!";
    open my $output, '>', $tmpFile or die "can't open $file: $!";
    while (my $line = <$input>) {
      if ( $line =~ /pkg_repl|pkg_ronly/ ) {
	my $rhv = (split(/[()]/,(split(/pkg_repl|pkg_ronly/, $line))[1]))[1];
	chomp $rhv;
	$rhv =~ s/['" ]//g;
	my ($opn, $opv, $opa) = split(/,/, $rhv);
	my $rpa = $opa;
	$rpa = $defaultarch if ($opa =~ /DEFAULT/);
        open my $update, '<', $errata or die "can't open $file: $!";
        while (my $uline = <$update>) {
	  if ( $uline =~ /pkg_ronly.*['"]\Q$opn\E['"].*['"]\Q$rpa\E['"]/ ) {
	    $rhv = (split(/[()]/,(split(/pkg_ronly/, $uline))[1]))[1];
	    chomp $rhv;
	    $rhv =~ s/['" ]//g;
	    my ($upn, $upv, $upa) = split(/,/, $rhv);
	    if ( $opv ne $upv ) {
	      print "    $opn $opv $opa -> $upn $upv $upa\n";
	      $line =~ s/(['"])$opv(['"])/$1$upv$2/;
	      $changed = 1;
	    }
	  }
        } 
        close $update;
      }
      print $output $line;
    } 
    close $output;
    close $input;
    qx{cat $tmpFile > $file} if ($changed == 1);
    unlink $tmpFile;
  }
}

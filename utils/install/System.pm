# Copyright 1999 - 2000 by Paul Johnson (paul@pjcj.net)

# documentation at __END__

# Original author: Paul Johnson
# Created:         Fri 12 Mar 1999 10:25:51 am

use strict;

require 5.004;

package System;

use Exporter ();
use vars qw($VERSION @ISA @EXPORT);

$VERSION = do { my @r = (q$Revision: 1.1 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

@ISA = ("Exporter");
@EXPORT = ("sys", "dsys");

my $Command = 0;
my $Errors  = 0;
my $Verbose = 0;

sub import {
  my $class = shift;
  my $args = "@_";
  $Command = $args =~ /\bcommand\b/i;
  $Errors  = $args =~ /\berror\b/i;
  $Verbose = $args =~ /\bverbose\b/i;
  $Command ||= $Verbose;
  $Errors  ||= $Verbose;
  $class->export_to_level(1, "sys" ) if $args =~ /\bsys\b/i;
  $class->export_to_level(1, "dsys") if $args =~ /\bdsys\b/i;
}

sub sys {
  my (@command) = @_;
  local $| = 1;
  print "@command"; # if $Command;
  my $rc = 0xffff & system @command;
  print "\n" if $Command && !$rc && !$Verbose;
  ret($rc);
}

sub dsys {
  die "@_ failed" if sys @_;
}

sub ret {
  my ($rc) = @_;
  printf "  returned %#04x: ", $rc if $Errors && $rc;
  if ($rc == 0) {
    print "ran with normal exit\n" if $Verbose;
  } elsif ($rc == 0xff00) {
    print "command failed: $!\n" if $Errors;
  } elsif ($rc > 0x80) {
    $rc >>= 8;
    print "ran with non-zero exit status $rc\n" if $Errors;
  } else {
    print "ran with " if $Errors;
    if ($rc & 0x80) {
      $rc &= ~0x80;
      print "coredump from " if $Errors;
    }
    print "signal $rc\n" if $Errors;
  }
  $rc;
}

1

__END__

=head1 NAME

System - run a system command and check the result

=head1 SYNOPSIS

use System "command, verbose, errors";
sys qw(ls -al);

=head1 DESCRIPTION

The sys function runs a system command, checks result, and comments on
it.

=cut

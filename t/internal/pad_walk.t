#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Cwd        qw( realpath );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing is ok )];

# check_files discovers pad anon subs by walking each CV's pad tree with
# pad_cvs.  An Exporter-aliased sub is reachable from the glob of every
# package that imported it, so without a report-wide record of which CVs
# have already been walked the same CV is walked once per importing
# package.  Repeating the walk cannot change which subs are covered - every
# write into %Cvs is idempotent - so the redundant walks are pure waste.
# This test asserts the invariant that within a single check_files run no
# CV is walked more than once.

# Run a program that imports one sub into several packages under coverage,
# with pad_cvs and check_files wrapped in the child to count, within a
# single check_files run, how many pad_cvs calls land on a CV already
# walked in that run.  Return that redundant-walk count.
sub redundant_walks ($packages) {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));

  my $util = <<'PM';
package Util;
use Exporter 'import';
our @EXPORT_OK = qw( shared_sub );
sub shared_sub { $_[0] + 1 }
1;
PM

  my $prog = "use strict;\nuse warnings;\n";
  $prog .= <<'INSTR';
my %seen;
my $redundant = 0;
my $orig = \&Devel::Cover::pad_cvs;
no warnings qw( redefine prototype );
*Devel::Cover::pad_cvs = sub {
  my $cv = $_[0];
  $redundant++ if ref $cv && $seen{$$cv}++;
  goto &$orig;
};
my $check = \&Devel::Cover::check_files;
*Devel::Cover::check_files = sub {
  %seen      = ();
  $redundant = 0;
  my @r = $check->(@_);
  print "REDUNDANT:$redundant\n";
  @r;
};
INSTR
  $prog
    .= "package Pkg$_;\nuse Util qw( shared_sub );\n"
    . "sub run { shared_sub($_) }\n"
    for 1 .. $packages;
  $prog .= "package main;\n";
  $prog .= "Pkg${_}::run();\n" for 1 .. $packages;

  my %write = (
    File::Spec->catfile($tmpdir, "Util.pm") => $util,
    File::Spec->catfile($tmpdir, "prog.pl") => $prog,
  );
  for my $path (sort keys %write) {
    open my $fh, ">", $path or die "Cannot write $path: $!";
    print $fh $write{$path};
    close $fh or die "Cannot close $path: $!";
  }

  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  my $program  = File::Spec->catfile($tmpdir, "prog.pl");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$tmpdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0,-select,Util,-ignore,."
    . " $program 2>&1";
  my $out = `$cmd`;
  my ($redundant) = $out =~ /^REDUNDANT:(\d+)$/m;
  diag $out unless defined $redundant;
  $redundant
}

sub test_no_redundant_walks () {
  my $redundant = redundant_walks(8);
  is $redundant, 0,
    "no CV is walked more than once in a single check_files run";
}

sub main () {
  test_no_redundant_walks;
  done_testing;
}

main;

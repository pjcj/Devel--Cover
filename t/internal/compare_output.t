#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Test::More import => [qw( done_testing is isnt note )];

use File::Spec ();
use File::Temp qw( tempdir );

my $Driver_code = <<'PERL';
use strict;
use warnings;

use Devel::Cover::Test ();

my ($mode, $truncated) = @ARGV;
if ($mode eq "differences") {
  eval q{ package Devel::Cover::Test; use Test::Differences; 1 } or die $@;
}

my @golden = ("Total 100.0\n", "MISSING LINE A\n", "MISSING LINE B\n");
my $live   = $truncated ? $golden[0] : join "", @golden;

my $self = bless {
  cover       => [@golden],
  differences => $mode eq "differences" ? 1 : 0,
  debug       => 0,
  no_coverage => 0,
  changes     => [],
}, "Devel::Cover::Test";

Test::More::plan(tests => $self->{differences} ? 1 : scalar @golden);
open my $fh, "<", \$live or die "Cannot open in-memory handle: $!";
$self->_compare_cover_output($fh);
PERL

my $Driver;

sub write_driver () {
  my $tmpdir = tempdir(CLEANUP => 1);
  my $driver = File::Spec->catfile($tmpdir, "driver.pl");
  open my $fh, ">", $driver or die "Cannot create $driver: $!";
  print $fh $Driver_code;
  close $fh or die "Cannot close $driver: $!";
  $driver
}

sub run_driver ($mode, $truncated) {
  my $cmd = join " ", $^X, "-Ilib", "-It/lib", $Driver, $mode, $truncated,
    "2>&1";
  my $output = `$cmd`;
  ($? >> 8, $output)
}

sub test_truncated_differences () {
  my ($exit, $output) = run_driver("differences", 1);
  isnt $exit, 0, "truncated cover output fails in differences mode";
}

sub test_complete_differences () {
  my ($exit, $output) = run_driver("differences", 0);
  is $exit, 0, "matching cover output passes in differences mode";
}

sub test_truncated_plain () {
  my ($exit, $output) = run_driver("plain", 1);
  isnt $exit, 0, "truncated cover output fails in plain mode";
}

sub main () {
  $Driver = write_driver;
  if (eval "use Test::Differences; 1") {
    test_truncated_differences;
    test_complete_differences;
  } else {
    note "Test::Differences not installed - differences mode not tested";
  }
  test_truncated_plain;
  done_testing;
}

main;

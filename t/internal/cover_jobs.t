#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Cwd                qw( getcwd );
use File::Spec         ();
use File::Temp         qw( tempdir );
use FindBin            ();
use lib $FindBin::Bin, qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing like note plan unlike )];

my $Project   = getcwd;
my $Cover     = File::Spec->catfile($Project, "bin", "cover");
my $Blib_lib  = File::Spec->catdir($Project, "blib", "lib");
my $Blib_arch = File::Spec->catdir($Project, "blib", "arch");

unless (-f $Cover && -d $Blib_lib && -d $Blib_arch) {
  plan skip_all => "build artefacts missing - run after `make`";
  exit;
}

if ($^O eq "MSWin32") {
  plan skip_all => "POSIX shell helper not portable to Windows";
  exit;
}

my $Tmpdir = tempdir(CLEANUP => 1);

# A stand-in for `make` that simply reports what HARNESS_OPTIONS it saw.
my $Fake_make = File::Spec->catfile($Tmpdir, "fake-make");
{
  open my $fh, ">", $Fake_make or die "open $Fake_make: $!";
  print {$fh} <<'SH';
#!/bin/sh
printf 'CHILD_HARNESS_OPTIONS=%s\n' "$HARNESS_OPTIONS"
exit 0
SH
  close $fh or die "close $Fake_make: $!";
  chmod 0755, $Fake_make;
}

my $Db = File::Spec->catdir($Tmpdir, "cover_db");
mkdir $Db or die "mkdir $Db: $!";

sub run_cover (@extra_args) {
  my $cmd = join " ", $^X, $Cover, "-test", "-silent", "-no-summary",
    "-no-gcov", "-no-delete", "-make", $Fake_make, @extra_args, "-write", $Db;
  my $out = `$cmd 2>/dev/null`;
  note $out;
  $out
}

sub test_long_form () {
  like run_cover("-jobs", 3), qr/CHILD_HARNESS_OPTIONS=.*\bj3\b/,
    "child harness sees HARNESS_OPTIONS=j3 when -jobs 3 passed";
}

sub test_short_form () {
  like run_cover("-j", 5), qr/CHILD_HARNESS_OPTIONS=.*\bj5\b/,
    "short form -j 5 also propagates";
}

sub test_no_jobs () {
  unlike run_cover(), qr/CHILD_HARNESS_OPTIONS=.*\bj\d/,
    "no -jobs leaves HARNESS_OPTIONS unset";
}

sub test_appends_to_existing () {
  local $ENV{HARNESS_OPTIONS} = "c";
  like run_cover("-jobs", 4), qr/CHILD_HARNESS_OPTIONS=c:j4\b/,
    "-jobs appends to existing HARNESS_OPTIONS";
}

sub main () {
  local $ENV{PERL5LIB} = join ":", $Blib_lib, $Blib_arch,
    ($ENV{PERL5LIB} // ());
  local $ENV{HARNESS_OPTIONS} = "";

  test_long_form;
  test_short_form;
  test_no_jobs;
  test_appends_to_existing;
  done_testing;
}

main;

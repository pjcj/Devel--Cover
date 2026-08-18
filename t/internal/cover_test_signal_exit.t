#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Config     qw( %Config );
use Cwd        qw( getcwd );
use File::Spec ();
use File::Temp qw( tempdir );

use Test::More import => [qw( done_testing is like note plan )];

if ($^O eq "MSWin32") {
  plan skip_all => "test drives a stub Build shell script with signals";
  exit;
}

my $Project   = getcwd;
my $Cover     = File::Spec->catfile($Project, "bin", "cover");
my $Blib_lib  = File::Spec->catdir($Project, "blib", "lib");
my $Blib_arch = File::Spec->catdir($Project, "blib", "arch");

unless (-f $Cover && -d $Blib_lib && -d $Blib_arch) {
  plan skip_all => "build artefacts missing - run after `make`";
  exit;
}

sub write_build ($dir, $body) {
  my $build = File::Spec->catfile($dir, "Build");
  open my $fh, ">", $build or die "open $build: $!";
  print $fh "#!/bin/sh\n$body\n";
  close $fh or die "close $build: $!";
  chmod 0755, $build or die "chmod $build: $!";
}

sub run_cover ($dir, @args) {
  my $args = join " ", map "'$_'", @args;
  my $out = `cd '$dir' && '$^X' '$Cover' -test -nogcov -report text $args 2>&1`;
  note $out;
  ($? >> 8, $out)
}

sub test_signal_death () {
  my $dir = tempdir(CLEANUP => 1);
  write_build($dir, 'kill -KILL $$');
  my ($rc, $out) = run_cover($dir);
  is $rc, 137, "signal-killed test run exits 128 plus the signal";
}

sub test_plain_failure () {
  my $dir = tempdir(CLEANUP => 1);
  write_build($dir, "exit 3");
  my ($rc, $out) = run_cover($dir);
  is $rc, 3, "failing test run passes its exit status through";
}

sub test_unrunnable_command () {
  my $dir = tempdir(CLEANUP => 1);
  my ($rc, $out) = run_cover($dir, "-make", "/no/such/prog");
  is $rc, 255, "unrunnable test command exits 255";
  like $out, qr/Can't run/, "unrunnable test command reports the error";
}

sub main () {
  local $ENV{PERL5LIB} = join $Config{path_sep}, $Blib_lib, $Blib_arch,
    ($ENV{PERL5LIB} // ());

  test_signal_death;
  test_plain_failure;
  test_unrunnable_command;
  done_testing;
}

main;

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Test::More import => [qw( done_testing is like ok plan )];

use Cwd        qw( abs_path );
use File::Path qw( mkpath );
use File::Spec ();
use File::Temp qw( tempdir );

use lib "utils";
use Devel::Cover::BuildUtils qw( find_prove prove_command run_prove );

sub write_exe ($path, $contents) {
  open my $fh, ">", $path or die "Cannot create $path: $!";
  print $fh $contents;
  close $fh or die "Cannot close $path: $!";
  chmod 0755, $path or die "Cannot chmod $path: $!";
}

sub perl_beside ($dir, @siblings) {
  mkpath $dir;
  write_exe(File::Spec->catfile($dir, "perl"),  "#!/bin/sh\nexit 0\n");
  write_exe(File::Spec->catfile($dir, $_->[0]), "#!/bin/sh\nexit $_->[1]\n")
    for @siblings;
  File::Spec->catfile($dir, "perl")
}

sub test_find_prove_relative_symlink () {
  my $tmpdir = tempdir(CLEANUP => 1);
  my $real   = File::Spec->catdir($tmpdir, "real", "bin");
  my $link   = File::Spec->catdir($tmpdir, "link", "bin");
  perl_beside($real, ["prove", 0]);
  mkpath $link;
  symlink "../../real/bin/perl", File::Spec->catfile($link, "perl")
    or die "Cannot symlink: $!";

  local $^X = File::Spec->catfile($link, "perl");
  is find_prove, File::Spec->catfile(abs_path($real), "prove"),
    "find_prove resolves a relative symlink to the real prove";
}

sub test_run_prove_dies_without_prove () {
  my $tmpdir = tempdir(CLEANUP => 1);
  local $^X = perl_beside(File::Spec->catdir($tmpdir, "bin"));
  my $ok = eval { run_prove; 1 };
  ok !$ok, "run_prove dies when no prove is found";
  like $@, qr/No prove found/, "the error names the problem";
}

sub test_run_prove_failing_prove () {
  my $tmpdir = tempdir(CLEANUP => 1);
  local $^X = perl_beside(File::Spec->catdir($tmpdir, "bin"), ["prove", 1]);
  ok !run_prove, "run_prove returns false when prove fails";
}

sub test_prove_command_contract () {
  my $cmd = eval { prove_command };
  is $@, "", "prove_command does not die on the real perl";
  ok !defined $cmd || $cmd =~ /-brj\d+ t$/,
    "prove_command returns undef or a -brj command";
}

sub main () {
  plan skip_all => "no shell stubs on Windows" if $^O eq "MSWin32";

  test_find_prove_relative_symlink;
  test_run_prove_dies_without_prove;
  test_run_prove_failing_prove;
  test_prove_command_contract;
  done_testing;
}

main;

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Cwd        qw( getcwd );
use File::Spec ();
use File::Temp qw( tempdir );

use Test::More import => [qw( done_testing is like note plan )];

my $Project   = getcwd;
my $Blib_lib  = File::Spec->catdir($Project, "blib", "lib");
my $Blib_arch = File::Spec->catdir($Project, "blib", "arch");

unless (-d $Blib_lib && -d $Blib_arch) {
  plan skip_all => "build artefacts missing - run after `make`";
  exit;
}

sub run_child ($code) {
  my $dir     = tempdir(CLEANUP => 1);
  my $db      = File::Spec->catdir($dir, "db");
  my $program = File::Spec->catfile($dir, "program.pl");
  open my $fh, ">", $program or die "open $program: $!";
  print $fh $code;
  close $fh or die "close $program: $!";
  my $out = qq("$^X" "-I$Blib_lib" "-I$Blib_arch" )
    . qq("-MDevel::Cover=-silent,1,-db,$db" "$program" 2>&1);
  $out = `$out`;
  note $out if length $out;
  ($?, $out)
}

sub test_call_from_main () {
  my ($status, $out) = run_child 'Devel::Cover::set_last_end(); print "done"';
  is $status, 0, "set_last_end from package main exits cleanly";
  like $out, qr/done/, "the program runs to completion";
}

sub test_call_from_module_package () {
  my ($status, $out)
    = run_child "package Devel::Cover; set_last_end();"
    . ' my @ends = get_ends()->ARRAY; print scalar @ends';
  is $status, 0, "set_last_end from Devel::Cover exits cleanly";
  like $out, qr/^[1-9]\d*$/m, "get_ends returns a non-empty list";
}

sub test_double_call () {
  my ($status, $out)
    = run_child 'Devel::Cover::set_last_end() for 1 .. 2; print "done"';
  is $status, 0, "calling set_last_end twice exits cleanly";
}

sub test_collect_inits () {
  my ($status, $out) = run_child 'Devel::Cover::collect_inits(); print "done"';
  is $status, 0, "collect_inits from package main exits cleanly";
}

sub test_collect_inits_with_init_block () {
  my ($status, $out)
    = run_child "INIT { 1 } BEGIN { Devel::Cover::collect_inits() }"
    . ' my @ends = Devel::Cover::get_ends()->ARRAY; print scalar @ends';
  is $status, 0, "collect_inits with an INIT block exits cleanly";
  like $out, qr/^[1-9]\d*$/m, "the INIT block CV is snapshotted";
}

sub main () {
  test_call_from_main;
  test_call_from_module_package;
  test_double_call;
  test_collect_inits;
  test_collect_inits_with_init_block;
  done_testing;
}

main;

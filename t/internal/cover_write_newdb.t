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

use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing is is_deeply like unlike )];
use Devel::Cover::Test::Showcase qw(
  create_cover_db
  run_cover
  setup_lib_dir
);

sub structure_names ($db) {
  my $dir = File::Spec->catdir($db, "structure");
  opendir my $dh, $dir or return [];
  my @names = sort grep !/^\.|\.lock$/, readdir $dh;
  closedir $dh;
  \@names
}

sub test_write_new_name ($tmpdir, $cover_db) {
  my $new = File::Spec->catdir($tmpdir, "new_db");
  my ($out, $exit) = run_cover("-write", $new, $cover_db);
  is $exit, 0, "-write to a new name exits 0" or diag $out;
  is_deeply structure_names($new), structure_names($cover_db),
    "-write to a new name copies the structure";
  $new
}

sub test_report_new_name ($new) {
  my ($out, $exit) = run_cover("-report", "text", $new);
  is $exit, 0, "text report on the copy exits 0" or diag $out;
  unlike $out, qr/Can't locate structure/,
    "text report on the copy finds the structure";
  like $out, qr/^Trivial\.pm\s+100\.0/m,
    "text report on the copy has statement coverage for Trivial.pm";
}

sub test_write_in_place ($cover_db) {
  my $before = structure_names($cover_db);
  my ($out, $exit) = run_cover($cover_db, "-write");
  is $exit, 0, "-write in place exits 0" or diag $out;
  is_deeply structure_names($cover_db), $before,
    "-write in place keeps the structure";
}

sub test_write_merge ($tmpdir, $libdir, $cover_db) {
  my $other_db = create_cover_db(tempdir(CLEANUP => 1), $libdir);
  my $merged   = File::Spec->catdir($tmpdir, "merged_db");
  my ($out, $exit) = run_cover("-write", $merged, $cover_db, $other_db);
  is $exit, 0, "-write with a merge exits 0" or diag $out;
  is_deeply structure_names($merged), structure_names($cover_db),
    "-write with a merge writes the structure";
}

sub main () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);
  my $new      = test_write_new_name($tmpdir, $cover_db);
  test_report_new_name($new);
  test_write_in_place($cover_db);
  test_write_merge($tmpdir, $libdir, $cover_db);
  done_testing;
}

main;

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use v5.20.0;
use strict;
use warnings;
use feature qw( signatures );
no warnings qw( experimental::signatures );

use Test::More import => [ qw( done_testing is like ok ) ];

use Cwd            qw( realpath );
use File::Basename qw( dirname );
use File::Path     qw( make_path );
use File::Spec     ();
use File::Temp     qw( tempdir );

use lib qw( ./lib ./blib/lib ./blib/arch );

use Devel::Cover::DB ();

my $Test_dir = dirname(__FILE__);
my $Root     = realpath(File::Spec->catdir($Test_dir, "..", ".."));
my $Cover    = File::Spec->catfile($Root, "bin", "cover");

sub run_cover (@args) {
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd = join " ", "$^X -Iblib/lib -Iblib/arch", $Cover, @args;
  my $out = `$cmd 2>&1`;
  ($out, $? >> 8)
}

sub write_module ($path, $pkg, $body) {
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh "package $pkg;\n$body\n1\n";
  close $fh or die "Cannot close $path: $!"
}

sub setup_lib_dir () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $libdir = File::Spec->catdir($tmpdir, "lib");
  make_path($libdir);

  write_module(
    File::Spec->catfile($libdir, "Covered.pm"),
    "Covered",
    'sub hello { "hello" }'
  );
  write_module(
    File::Spec->catfile($libdir, "Uncovered.pm"),
    "Uncovered",
    'sub world { "world" }'
  );

  # blib subdir - should be excluded by scan_select_dirs
  my $blib = File::Spec->catdir($libdir, "blib", "lib");
  make_path($blib);
  write_module(
    File::Spec->catfile($blib, "BlibMod.pm"),
    "BlibMod", "sub x { 1 }"
  );

  # non-pm file - should be excluded
  open my $fh, ">", File::Spec->catfile($libdir, "README.txt")
    or die "Cannot create README: $!";
  close $fh or die $!;

  ($tmpdir, $libdir)
}

sub create_cover_db ($tmpdir, $libdir) {
  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  my $select   = quotemeta $libdir;

  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};

  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$libdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0,-select,$select"
    . ' -e "use Covered; Covered::hello()" 2>&1';
  my $out = `$cmd`;
  die "Failed to create cover_db:\n$out\n" if $?;

  $cover_db
}

# GREEN: --select_dir scans .pm/.pl files and persists the list in the DB,
# excluding blib/ subdirectories and non-Perl files.
sub test_scan () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = File::Spec->catdir($tmpdir, "cover_db_scan");
  make_path($cover_db);

  my ($out, $exit)
    = run_cover("--select_dir", $libdir, "--write", "--silent", $cover_db);
  is $exit, 0, "cover --select_dir exits 0";

  my $db    = Devel::Cover::DB->new(db => $cover_db);
  my @files = sort $db->files;

  is scalar @files, 2, "exactly two files found";
  ok grep(/Covered\.pm$/,   @files), "Covered.pm in files";
  ok grep(/Uncovered\.pm$/, @files), "Uncovered.pm in files";
  ok !grep(/blib/,          @files), "blib files excluded";
  ok !grep(/\.txt$/,        @files), "non-pm files excluded";
}

# RED (step 3): when $db->{files} lists a file absent from all runs,
# $db->cover should include it as an uncompiled entry with the
# {meta}{uncompiled} flag set.
sub test_uncompiled_in_cover () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $uncovered_pm = File::Spec->catfile($libdir, "Uncovered.pm");

  # Empty cover_db - no runs, so Uncovered.pm has no coverage data.
  # Simulate what scan_select_dirs would write into $db->{files}.
  my $cover_db = File::Spec->catdir($tmpdir, "cover_db_unit");
  make_path($cover_db);
  my $db = Devel::Cover::DB->new(db => $cover_db);
  $db->{files} = [$uncovered_pm];

  my $cover    = $db->cover;
  my $file_obj = $cover->file($uncovered_pm);

  ok defined $file_obj, "Uncovered.pm appears in cover()";
  ok $file_obj && $file_obj->{meta}{uncompiled},
    "Uncovered.pm has uncompiled meta flag";
}

# RED (steps 3-5): the text report summary should list uncovered files
# (those in --select_dir but absent from all runs) with n/a for every
# coverage criterion.
sub test_text_report () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "text", "--silent", $cover_db
  );

  is $exit, 0, "cover --report text exits 0";
  like $out, qr/Uncovered\.pm/,       "Uncovered.pm appears in report";
  like $out, qr/Uncovered\.pm.*n\/a/, "n/a shown on Uncovered.pm row";
}

sub main () {
  test_scan;
  test_uncompiled_in_cover;
  test_text_report;
  done_testing;
}

main;

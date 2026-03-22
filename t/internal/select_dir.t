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

use FindBin ();
use lib $FindBin::Bin, qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [ qw( done_testing is like ok ) ];

use File::Path qw( make_path );
use File::Spec ();

use Devel::Cover::DB ();
use TestHelper       qw( create_cover_db run_cover setup_lib_dir );

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

# when $db->{files} lists a file absent from all runs, $db->cover should
# include it as an uncompiled entry with the {meta}{uncompiled} flag set.
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

  my $have_ppi = eval { require PPI; 1 };
  if ($have_ppi) {
    ok $file_obj->{meta}{counts}, "counts present when PPI available";
    ok $file_obj->{meta}{counts}{subroutine},
      "subroutine count is non-zero";
  } else {
    ok !$file_obj->{meta}{counts}, "no counts without PPI";
  }
}

# the text report summary should list uncovered files (those in --select_dir
# but absent from all runs).  When PPI is available, Static analysis provides
# real counts so values show 0.0; otherwise they show n/a.
sub test_text_report () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "text", "--silent", $cover_db
  );

  is $exit, 0, "cover --report text exits 0";
  like $out, qr/Uncovered\.pm/, "Uncovered.pm appears in report";

  my $have_ppi = eval { require PPI; 1 };
  if ($have_ppi) {
    like $out, qr/Uncovered\.pm.*\b0\.0\b/,
      "0.0 shown on Uncovered.pm row (PPI available)";
  } else {
    like $out, qr/Uncovered\.pm.*n\/a/,
      "n/a shown on Uncovered.pm row (no PPI)";
  }
}

sub main () {
  test_scan;
  test_uncompiled_in_cover;
  test_text_report;
  done_testing;
}

main;

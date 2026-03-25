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

use Test::More import => [ qw( done_testing is is_deeply like ok ) ];

eval "use Test::Differences";
my $Has_test_diff = $INC{"Test/Differences.pm"};

use File::Path qw( make_path );
use File::Spec ();

use Devel::Cover::DB ();
use TestHelper       qw( create_cover_db run_cover setup_lib_dir );

sub have_ppi () { eval { require PPI; 1 } }

# Extract uncovered file summary lines from text report output, normalising
# away temp-dir prefixes so comparisons are stable.
sub _uncovered_summary ($out) { [
  sort map {
    my ($file, $rest) = /(Uncovered\/\w+\.pm)\s+(.*)/;
    my @vals = ($rest =~ /([\d.]+|n\/a)/g);
    join "  ", $file, @vals
  } grep /Uncovered\//,
  split /\n/,
  $out,
] }

# --select_dir scans .pm/.pl files and persists the list in the DB, excluding
# blib/ subdirectories and non-Perl files.
sub test_scan () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = File::Spec->catdir($tmpdir, "cover_db_scan");
  make_path($cover_db);

  my ($out, $exit)
    = run_cover("--select_dir", $libdir, "--write", "--silent", $cover_db);
  is $exit, 0, "cover --select_dir exits 0";

  my $db    = Devel::Cover::DB->new(db => $cover_db);
  my @files = sort $db->files;

  is @files, 8, "exactly eight files found";
  ok grep(/Covered\/Calc\.pm$/,      @files), "Covered/Calc.pm in files";
  ok grep(/Covered\/Full\.pm$/,      @files), "Covered/Full.pm in files";
  ok grep(/Covered\/Trivial\.pm$/,   @files), "Covered/Trivial.pm in files";
  ok grep(/Covered\/Utils\.pm$/,     @files), "Covered/Utils.pm in files";
  ok grep(/Uncovered\/Calc\.pm$/,    @files), "Uncovered/Calc.pm in files";
  ok grep(/Uncovered\/Full\.pm$/,    @files), "Uncovered/Full.pm in files";
  ok grep(/Uncovered\/Trivial\.pm$/, @files), "Uncovered/Trivial.pm in files";
  ok grep(/Uncovered\/Utils\.pm$/,   @files), "Uncovered/Utils.pm in files";
  ok !grep(/blib/,                   @files), "blib files excluded";
  ok !grep(/\.txt$/,                 @files), "non-pm files excluded";
}

# When $db->{files} lists a file absent from all runs, $db->cover should include
# it as an uncompiled entry with the meta flag set.
sub test_uncompiled_in_cover () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $uncovered_pm = File::Spec->catfile($libdir, "Uncovered", "Calc.pm");

  my $cover_db = File::Spec->catdir($tmpdir, "cover_db_unit");
  make_path($cover_db);
  my $db = Devel::Cover::DB->new(db => $cover_db);
  $db->{files} = [$uncovered_pm];

  my $cover    = $db->cover;
  my $file_obj = $cover->file($uncovered_pm);

  ok defined $file_obj, "Uncovered/Calc.pm appears in cover()";
  ok $file_obj && $file_obj->{meta}{uncompiled},
    "Uncovered/Calc.pm has uncompiled meta flag";

  if (have_ppi) {
    ok $file_obj->{meta}{counts}, "counts present when PPI available";
    ok $file_obj->{meta}{counts}{subroutine}, "subroutine count is non-zero";
    ok $file_obj->{meta}{counts}{branch},     "branch count is non-zero";
    ok $file_obj->{meta}{counts}{condition},  "condition count is non-zero";
  } else {
    ok !$file_obj->{meta}{counts}, "no counts without PPI";
  }
}

# The text report should list uncovered files with all criteria columns
# populated when PPI is available.
sub test_text_report () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "text", "--silent", $cover_db
  );

  is $exit, 0, "cover --report text exits 0";
  like $out, qr/Covered\/Calc\.pm/, "Covered/Calc.pm in report";

  my $got = _uncovered_summary($out);
  my $expected;
  if (have_ppi) {
    $expected = [
      sort "Uncovered/Calc.pm  0.0  0.0  0.0  0.0  0.0  n/a  0.0",
      "Uncovered/Full.pm  0.0  0.0  0.0  0.0  0.0  n/a  0.0",
      "Uncovered/Trivial.pm  0.0  n/a  n/a  0.0  0.0  n/a  0.0",
      "Uncovered/Utils.pm  0.0  0.0  n/a  0.0  0.0  n/a  0.0",
    ];
  } else {
    $expected = [
      sort "Uncovered/Calc.pm  n/a  n/a  n/a  n/a  n/a  n/a  n/a",
      "Uncovered/Full.pm  n/a  n/a  n/a  n/a  n/a  n/a  n/a",
      "Uncovered/Trivial.pm  n/a  n/a  n/a  n/a  n/a  n/a  n/a",
      "Uncovered/Utils.pm  n/a  n/a  n/a  n/a  n/a  n/a  n/a",
    ];
  }
  if ($Has_test_diff) {
    eq_or_diff($got, $expected, "uncovered file summary");
  } else {
    is_deeply($got, $expected, "uncovered file summary");
  }
}

sub main () {
  test_scan;
  test_uncompiled_in_cover;
  test_text_report;
  done_testing;
}

main;

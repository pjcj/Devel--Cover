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

use File::Spec ();
use Test::More import => [ qw( done_testing is like ok plan ) ];
use TestHelper qw( create_cover_db run_cover setup_lib_dir );

for my $mod (qw( HTML::Entities Template )) {
  eval "require $mod; 1" or do {
    plan skip_all => "$mod not available";
    exit;
  };
}

# Html_crisp report for a db with --select_dir:
# - Uncovered.pm (never loaded) appears in the summary index
# - Uncovered.pm has no per-file detail page
# - Covered.pm does have a per-file detail page
sub test_html_crisp_report () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);
  my $outdir   = File::Spec->catdir($tmpdir, "html");

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "html_crisp",
    "--outputdir",  $outdir, "--silent", $cover_db
  );

  is $exit, 0, "cover --report html_crisp exits 0";

  my $index = File::Spec->catfile($outdir, "index.html");
  ok -e $index, "index.html was generated";

  open my $fh, "<", $index or die "Cannot read $index: $!";
  my $content = do { local $/; <$fh> };
  close $fh or die "Cannot close $index: $!";

  like $content, qr/Uncovered\.pm/, "Uncovered.pm appears in index";

  my $have_ppi = eval { require PPI; 1 };
  if ($have_ppi) {
    like $content, qr/Uncovered\.pm.*\b0\.0\b/s,
      "0.0 shown for Uncovered.pm (PPI available)";
  } else {
    like $content, qr/Uncovered\.pm.*n\/a/s,
      "n/a shown for Uncovered.pm (no PPI)";
  }

  # Detail page filenames are the full path with \W replaced by '-'.
  # Filter out index.html; look for pages matching each module's basename.
  my @detail_pages    = grep !/index\.html$/,        glob "$outdir/*.html";
  my @covered_pages   = grep /-Covered-pm\.html$/,   @detail_pages;
  my @uncovered_pages = grep /-Uncovered-pm\.html$/, @detail_pages;

  ok @covered_pages,    "detail page for Covered.pm exists";
  ok !@uncovered_pages, "no detail page for Uncovered.pm";
}

sub main () {
  test_html_crisp_report;
  done_testing;
}

main;

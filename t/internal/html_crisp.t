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

sub _slurp ($path) {
  open my $fh, "<", $path or die "Cannot read $path: $!";
  my $content = do { local $/; <$fh> };
  close $fh or die "Cannot close $path: $!";
  $content
}

# Html_crisp report for a db with --select_dir:
# - All four modules appear in the summary index
# - Uncovered modules have no per-file detail pages
# - Covered modules do have per-file detail pages
# - When PPI is available, uncovered modules show 0.0
sub test_html_crisp_report () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);
  my $outdir   = File::Spec->catdir($tmpdir, "html");

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "html_crisp",
    "--outputdir",  $outdir, "--silent", $cover_db
  );

  is $exit, 0, "cover --report html_crisp exits 0";

  my $index = File::Spec->catfile($outdir, "coverage.html");
  ok -e $index, "coverage.html was generated";

  my $content = _slurp($index);

  # All eight modules appear in the index
  like $content, qr/Covered\/Calc\.pm/,      "Covered/Calc.pm in index";
  like $content, qr/Covered\/Full\.pm/,      "Covered/Full.pm in index";
  like $content, qr/Covered\/Trivial\.pm/,   "Covered/Trivial.pm in index";
  like $content, qr/Covered\/Utils\.pm/,     "Covered/Utils.pm in index";
  like $content, qr/Uncovered\/Calc\.pm/,    "Uncovered/Calc.pm in index";
  like $content, qr/Uncovered\/Full\.pm/,    "Uncovered/Full.pm in index";
  like $content, qr/Uncovered\/Trivial\.pm/, "Uncovered/Trivial.pm in index";
  like $content, qr/Uncovered\/Utils\.pm/,   "Uncovered/Utils.pm in index";

  # When PPI is available, uncovered files show 0.0
  my $have_ppi = eval { require PPI; 1 };
  if ($have_ppi) {
    like $content, qr/Uncovered\/Calc\.pm.*?\b0\.0\b/s,
      "0.0 shown for Uncovered/Calc.pm (PPI available)";
    like $content, qr/Uncovered\/Utils\.pm.*?\b0\.0\b/s,
      "0.0 shown for Uncovered/Utils.pm (PPI available)";
  } else {
    like $content, qr/Uncovered\/Calc\.pm.*?n\/a/s,
      "n/a shown for Uncovered/Calc.pm (no PPI)";
    like $content, qr/Uncovered\/Utils\.pm.*?n\/a/s,
      "n/a shown for Uncovered/Utils.pm (no PPI)";
  }

  # Detail pages exist for all modules (covered and uncovered).
  my @detail_pages = grep !/index\.html$/, glob "$outdir/*.html";

  ok( (grep /Covered-Calc-pm\.html$/,    @detail_pages),
    "detail page for Covered/Calc.pm exists" );
  ok( (grep /Covered-Utils-pm\.html$/,   @detail_pages),
    "detail page for Covered/Utils.pm exists" );
  ok( (grep /Uncovered-Calc-pm\.html$/,  @detail_pages),
    "detail page for Uncovered/Calc.pm exists" );
  ok( (grep /Uncovered-Utils-pm\.html$/, @detail_pages),
    "detail page for Uncovered/Utils.pm exists" );

  # Untested detail pages contain the untested badge.
  my $uncov_page = (grep /Uncovered-Calc-pm\.html$/, @detail_pages)[0];
  my $uncov_html = _slurp($uncov_page);
  like $uncov_html, qr/untested-badge/,
    "untested detail page has badge";
  like $uncov_html, qr/untested-page/,
    "untested detail page has dimmed wrapper";
}

sub main () {
  test_html_crisp_report;
  done_testing;
}

main;

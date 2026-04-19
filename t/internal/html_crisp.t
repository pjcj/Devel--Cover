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
use Test::More import => [qw( done_testing is like ok plan unlike )];
use Devel::Cover::Test::Showcase qw(
  create_cover_db
  run_cover
  setup_lib_dir
  slurp
);

eval "require HTML::Entities; 1" or do {
  plan skip_all => "HTML::Entities not available";
  exit;
};

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
    "--outputdir",  $outdir, "--silent", $cover_db,
  );

  is $exit, 0, "cover --report html_crisp exits 0";

  my $index = File::Spec->catfile($outdir, "coverage.html");
  ok -e $index, "coverage.html was generated";

  my $content = slurp($index);

  # All eight modules appear in the index
  like $content, qr/Covered\/Calc\.pm/,      "Covered/Calc.pm in index";
  like $content, qr/Covered\/Full\.pm/,      "Covered/Full.pm in index";
  like $content, qr/Covered\/Trivial\.pm/,   "Covered/Trivial.pm in index";
  like $content, qr/Covered\/Utils\.pm/,     "Covered/Utils.pm in index";
  like $content, qr/Uncovered\/Calc\.pm/,    "Uncovered/Calc.pm in index";
  like $content, qr/Uncovered\/Full\.pm/,    "Uncovered/Full.pm in index";
  like $content, qr/Uncovered\/Trivial\.pm/, "Uncovered/Trivial.pm in index";
  like $content, qr/Uncovered\/Utils\.pm/,   "Uncovered/Utils.pm in index";

  # With PPI, untested files show 0.0 for criteria PPI can estimate (statement,
  # subroutine, pod) and n/a for those it cannot (branch, condition).  Without
  # PPI, all criteria show "-" (no data).
  my $have_ppi = eval { require PPI; 1 };
  if ($have_ppi) {
    like $content, qr/Uncovered\/Calc\.pm.*?\b0\.0\b/s,
      "0.0 shown for Uncovered/Calc.pm (PPI estimates)";
    like $content, qr/Uncovered\/Utils\.pm.*?\b0\.0\b/s,
      "0.0 shown for Uncovered/Utils.pm (PPI estimates)";

    # SLOP tooltip and numeric value for untested files
    like $content, qr/Uncovered\/Calc\.pm.*?slop-detail/s,
      "SLOP tooltip present for Uncovered/Calc.pm";
    like $content, qr/Uncovered\/Calc\.pm.*?slop-tip-subs/s,
      "SLOP tooltip has worst subs for Uncovered/Calc.pm";
    # The SLOP cell should have a numeric data-value, not -1
    like $content, qr/Uncovered\/Calc\.pm.*?class="tip-hover"[^>]*>\s*[\d.]+/s,
      "SLOP cell has numeric value for Uncovered/Calc.pm";
  } else {
    like $content, qr/Uncovered\/Calc\.pm.*?<td[^>]*>\s*-\s/s,
      "- shown for Uncovered/Calc.pm (no PPI)";
    like $content, qr/Uncovered\/Utils\.pm.*?<td[^>]*>\s*-\s/s,
      "- shown for Uncovered/Utils.pm (no PPI)";
  }

  # Detail pages exist for all modules (covered and uncovered).
  my @detail_pages = grep !/index\.html$/, glob "$outdir/*.html";

  ok(
    (grep /Covered-Calc-pm\.html$/, @detail_pages),
    "detail page for Covered/Calc.pm exists",
  );
  ok(
    (grep /Covered-Utils-pm\.html$/, @detail_pages),
    "detail page for Covered/Utils.pm exists",
  );
  ok(
    (grep /Uncovered-Calc-pm\.html$/, @detail_pages),
    "detail page for Uncovered/Calc.pm exists",
  );
  ok(
    (grep /Uncovered-Utils-pm\.html$/, @detail_pages),
    "detail page for Uncovered/Utils.pm exists",
  );

  # Untested detail pages contain the untested badge.
  my $uncov_page = (grep /Uncovered-Calc-pm\.html$/, @detail_pages)[0];
  my $uncov_html = slurp($uncov_page);
  like $uncov_html, qr/untested-badge/, "untested detail page has badge";
  like $uncov_html, qr/untested-page/,
    "untested detail page has dimmed wrapper";

  # Tooltip behaviour on untested rows in the index.
  # Pull out each untested row and check it in isolation.
  my @untested_rows
    = $content =~ m{<tr class="dir-file untested"[^>]*>.*?</tr>}gs;
  ok @untested_rows >= 4, "at least four untested rows in index";

  if ($have_ppi) {
    for my $row (@untested_rows) {
      like $row, qr/tip-hover/,
        "untested-with-PPI row keeps tip-hover on cells";
      like $row, qr/glass-tip">\d+ \/ \d+</,
        "untested-with-PPI row has numeric tooltip";
    }
  } else {
    for my $row (@untested_rows) {
      # cells in this row should only carry the untested badge's tip-hover
      # (wrapped in a span), not any <td class="...tip-hover">
      unlike $row, qr/<td[^>]*class="[^"]*tip-hover/,
        "untested-without-PPI row: no tip-hover on <td>";
      unlike $row, qr/glass-tip">\d+ \/ \d+</,
        "untested-without-PPI row: no numeric tooltip";
      like $row, qr/class="untested-badge tip-hover"/,
        "untested-without-PPI row: badge has tip-hover";
      like $row, qr/glass-tip">Install PPI/,
        "untested-without-PPI row: install-PPI tooltip on badge";
    }
  }

  # Covered rows keep their tooltips regardless of PPI.
  my @covered_rows
    = $content =~ m{<tr class="dir-file"(?![^>]*untested)[^>]*>.*?</tr>}gs;
  ok @covered_rows >= 1, "at least one covered row in index";
  like $covered_rows[0], qr/<td[^>]*class="[^"]*tip-hover/,
    "covered row: cells have tip-hover";
  like $covered_rows[0], qr/glass-tip">\d+ \/ \d+</,
    "covered row: cells have numeric tooltip";

  # CSS rule that lets the untested-badge tooltip appear on hover.
  my $css = slurp(File::Spec->catfile($outdir, "assets", "style.css"));
  like $css,
    qr{tr\.untested td \.untested-badge\.tip-hover:hover\s*>\s*\.glass-tip},
    "CSS rule enables hover tooltip on untested badge";
}

sub main () {
  test_html_crisp_report;
  done_testing;
}

main;

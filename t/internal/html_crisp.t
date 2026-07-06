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

# Directory header rows show real aggregates and no links to files.
sub test_dir_header_rows ($content) {
  my @rows = $content =~ m{(<tr class="dir-header".*?</tr>)}gs;
  is @rows, 2, "index has two dir-header rows";

  for my $row (@rows) {
    my ($dir) = $row =~ m{data-dir="([^"]+)"};
    unlike $row, qr/cell-link/, "$dir dir-header row has no links";
  }

  my ($covered) = grep m{data-dir="Covered"}, @rows;
  ok $covered, "Covered dir-header row present";
  unlike $covered, qr/class="na"/,
    "Covered dir row has aggregates for all criteria";
  like $covered, qr{<dt>CC</dt><dd>[1-9]},
    "Covered dir row SCAR tooltip has non-zero CC";
  unlike $covered, qr/data-value="0" class="scar-val/,
    "Covered dir row SCAR is not a bare 0";
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
    "--outputdir",  $outdir, "--silent", $cover_db,
  );

  is $exit, 0, "cover --report html_crisp exits 0";

  my $index = File::Spec->catfile($outdir, "coverage.html");
  ok -e $index, "coverage.html was generated";

  my $content = slurp($index);

  test_dir_header_rows($content);

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

    # SCAR tooltip and numeric value for untested files
    like $content, qr/Uncovered\/Calc\.pm.*?scar-detail/s,
      "SCAR tooltip present for Uncovered/Calc.pm";
    like $content, qr/Uncovered\/Calc\.pm.*?scar-tip-subs/s,
      "SCAR tooltip has worst subs for Uncovered/Calc.pm";
    # The SCAR cell should have a numeric data-value, not -1
    like $content, qr/Uncovered\/Calc\.pm.*?class="tip-hover"[^>]*>\s*[\d.]+/s,
      "SCAR cell has numeric value for Uncovered/Calc.pm";
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

  # Three-panel structure on per-line detail blocks: per-logop cells matching
  # the cond % headline, the merged truth table relabelled as decision input
  # vectors, and the existing MC/DC pill row.
  my $covered_full = (grep /Covered-Full-pm\.html$/, glob "$outdir/*.html")[0];
  ok defined $covered_full, "Covered/Full.pm detail page exists";
  my $full_html = slurp($covered_full);
  like $full_html, qr/class="detail cond-cells"/,
    "html_crisp: cond-cells panel rendered on a covered file";
  like $full_html, qr{<div class="head"><span>Truth table</span>},
    "html_crisp: truth-table panel smallcaps heading rendered";
  like $full_html, qr{<span class="summary-text c[0-3]">\d+%},
    "html_crisp: truth-table panel carries summary %";
  like $full_html, qr/class="detail decision-vectors"/,
    "html_crisp: vectors panel wrapper class rendered";
  like $css, qr/\.cond-cells\b/, "html_crisp: cond-cells CSS rule present";
  like $css, qr/\.decision-vectors\b/,
    "html_crisp: decision-vectors CSS rule present";
}

sub main () {
  test_html_crisp_report;
  done_testing;
}

main;

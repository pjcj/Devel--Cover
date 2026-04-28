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
use Devel::Cover::Report::Html_crisp ();
use Devel::Cover::Test::Showcase     qw(
  create_cover_db
  run_cover
  setup_lib_dir
  slurp
);

eval "require HTML::Entities; 1" or do {
  plan skip_all => "HTML::Entities not available";
  exit;
};

# Shared state populated by _setup
my ($Tmpdir, $Libdir, $Outdir);
my %Golden;

# Generate golden TT output via run_cover (external process).
sub _setup () {
  return if $Tmpdir;
  ($Tmpdir, $Libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($Tmpdir, $Libdir);
  $Outdir = File::Spec->catdir($Tmpdir, "html");

  my ($out, $exit) = run_cover(
    "--select_dir", $Libdir, "--report", "html_crisp",
    "--outputdir",  $Outdir, "--silent", $cover_db,
  );
  die "TT report generation failed (exit $exit):\n$out\n" if $exit;

  for my $file (glob "$Outdir/*.html") {
    (my $name = $file) =~ s{.*/}{};
    $Golden{$name} = slurp($file);
  }
}

sub test_crit_name () {
  no warnings "once";
  local %Devel::Cover::Report::Html_crisp::R = (
    full  => { statement => "Statement", total => "total" },
    short => { statement => "stmt",      total => "total" },
  );

  my $got = Devel::Cover::Report::Html_crisp::crit_name("statement");
  is $got,
    '<span class="name-full">Statement</span>'
    . '<span class="name-short">stmt</span>',
    "_crit_name(statement) produces correct spans";

  my $got_total = Devel::Cover::Report::Html_crisp::crit_name("total");
  like $got_total, qr/name-full.*total/,  "_crit_name(total) has full span";
  like $got_total, qr/name-short.*total/, "_crit_name(total) has short span";
}

sub test_render_layout () {
  no warnings "once";
  local %Devel::Cover::Report::Html_crisp::R = (
    version        => "1.44",
    date           => "2026-04-08 12:00:00",
    perl_v         => "v5.40.0",
    os             => "linux",
    favicon_colour => "%232e7d32",
    report_id      => "/tmp/test_report",
    file_count     => 5,
  );

  my $got = Devel::Cover::Report::Html_crisp::render_layout(
    asset_prefix => "",
    title        => "Test Page",
    content      => "<p>Hello world</p>",
  );

  like $got, qr/<!DOCTYPE html>/,                 "layout: doctype";
  like $got, qr/<title>Test Page - Devel::Cover/, "layout: title";
  like $got, qr/assets\/style\.css/,              "layout: stylesheet";
  like $got, qr/assets\/app\.js/,                 "layout: script";
  like $got, qr/data-report-id/,                  "layout: report id";
  like $got, qr/data-file-count="5"/,             "layout: file count";
  like $got, qr/<p>Hello world<\/p>/,             "layout: content";
  like $got, qr/class="footer"/,                  "layout: footer";
  like $got, qr/1\.44 on 2026-04-08/,             "layout: version + date";
}

sub test_render_index () {
  my $got = $Golden{"coverage.html"};
  ok defined $got, "golden index exists";

  # Structural checks on the golden TT output - these will be
  # re-run against _render_index output once it replaces TT.
  like $got,   qr/<!DOCTYPE html>/,         "has doctype";
  like $got,   qr/<title>Coverage Summary/, "has summary title";
  like $got,   qr/class="file-table"/,      "has file table";
  like $got,   qr/class="worst-files"/,     "has worst files";
  like $got,   qr/class="dist-bar"/,        "has distribution bar";
  like $got,   qr/class="filter-bar"/,      "has filter bar";
  like $got,   qr/data-sort="slop"/,        "has SLOP column";
  unlike $got, qr/data-sort="risk"/,        "no risk column";
  like $got,   qr/Top SLOP/,                "worst files heading";
  like $got,   qr/Covered\/Calc\.pm/,       "Covered/Calc.pm present";
  like $got,   qr/Covered\/Full\.pm/,       "Covered/Full.pm present";
  like $got,   qr/Uncovered\/Calc\.pm/,     "Uncovered/Calc.pm present";
  like $got,   qr/Uncovered\/Full\.pm/,     "Uncovered/Full.pm present";
  like $got,   qr/untested-badge/,          "has untested badge";
  like $got,   qr/class="help-overlay"/,    "has help overlay";
  like $got,   qr/class="footer"/,          "has footer";
  like $got,   qr/Devel::Cover/,            "footer mentions Devel::Cover";
}

sub test_render_file_page () {
  # Find a covered file page
  my ($covered) = grep /Covered-Calc/, keys %Golden;
  ok defined $covered, "golden covered file page exists";
  my $got = $Golden{$covered};

  like $got, qr/<!DOCTYPE html>/,      "file: has doctype";
  like $got, qr/<title>.*Calc\.pm/,    "file: has file title";
  like $got, qr/class="source-table"/, "file: has source table";
  like $got, qr/class="file-nav"/,     "file: has navigation";
  like $got, qr/class="minimap"/,      "file: has minimap";
  like $got, qr/class="header-stats"/, "file: has stat badges";
  like $got, qr/class="help-overlay"/, "file: has help overlay";
  like $got, qr/coverage\.html/,       "file: links to summary";
  like $got, qr/class="ln"/,           "file: has line numbers";
  like $got, qr/class="count/,         "file: has count column";
  like $got, qr/class="src/,           "file: has source column";
}

sub test_tooltip_structure () {
  my $got = $Golden{"coverage.html"};

  # Unified glass tooltip system
  like $got, qr/class="glass-tip slop-detail"/,
    "tooltip: has glass-tip slop-detail";
  like $got, qr/class="slop-tip-metrics"/, "tooltip: has metrics section";
  like $got, qr/class="slop-tip-subs"/,    "tooltip: has subs section";
  like $got, qr/class="slop-tip-total"/,   "tooltip: has total section";

  # Colour coding inside tooltips
  like $got, qr/slop-tip-metrics.*?class="c[0-3]"/s,
    "tooltip: coverage value has colour class";
  like $got, qr/slop-tip-subs.*?class="c[0-3]"/s,
    "tooltip: sub entry has colour class";
}

sub test_glass_tooltips () {
  my $index = $Golden{"coverage.html"};

  # Single tooltip mechanism: tip-hover + glass-tip child
  like $index,   qr/class="[^"]*tip-hover/, "glass: has tip-hover class";
  like $index,   qr/class="glass-tip"/,     "glass: has glass-tip child";
  unlike $index, qr/class="[^"]*has-tip/,   "glass: no has-tip class";
  unlike $index, qr/data-tip="/,            "glass: no data-tip attributes";

  # File page SLOP badge uses tip-hover
  my ($covered) = grep /Covered-Calc/, keys %Golden;
  my $file_page = $Golden{$covered};
  like $file_page,   qr/stat-slop tip-hover/, "glass: SLOP badge has tip-hover";
  unlike $file_page, qr/slop-hover/,          "glass: no slop-hover class";
}

sub test_dir_row_slop () {
  my $got = $Golden{"coverage.html"};
  like $got, qr/dir-header.*?tip-hover.*?slop-detail/s,
    "dir row: has SLOP tooltip";
}

sub test_module_slop_badge () {
  my $got = $Golden{"coverage.html"};
  like $got, qr/stat-badge.*?slop\b/s, "header: has SLOP stat badge";
  like $got, qr/slop.*?help-toggle/s,  "header: SLOP badge before help button";
}

sub test_total_badge_filter () {
  my ($covered) = grep /Covered-Calc/, keys %Golden;
  ok defined $covered, "golden covered file page exists for total badge test";
  my $file_page = $Golden{$covered};

  like $file_page, qr/stat-badge[^"]*"[^>]*data-criterion="total"/,
    "file: total badge has data-criterion";
  like $file_page, qr/<kbd>t<\/kbd>/, "file: help mentions t key";

  my $app_js = slurp(File::Spec->catfile($Outdir, "assets", "app.js"));
  like $app_js, qr/t:\s*"total"/, "app.js: 't' keybinding maps to total filter";
  like $app_js, qr/crit\s*===\s*"total"/,
    "app.js: applyFilter special-cases total";
}

sub test_file_nav_keys () {
  my ($covered) = grep /Covered-Calc/, keys %Golden;
  my $file_page = $Golden{$covered};
  like $file_page, qr/<kbd>h<\/kbd> \/ <kbd>l<\/kbd> prev\/next file/,
    "file: help mentions h/l for file nav";
  unlike $file_page, qr/<kbd>\[<\/kbd>/, "file: help no longer mentions [";

  my $app_js = slurp(File::Spec->catfile($Outdir, "assets", "app.js"));
  like $app_js, qr/e\.key\s*===\s*"h"/, "app.js: h key handled";
  like $app_js, qr/e\.key\s*===\s*"l"/, "app.js: l key handled";
}

sub test_render_untested_page () {
  my ($untested) = grep /Uncovered-Calc/, keys %Golden;
  ok defined $untested, "golden untested file page exists";
  my $got = $Golden{$untested};

  like $got, qr/untested-page/,  "untested: has dimmed wrapper";
  like $got, qr/untested-badge/, "untested: has badge";
}

sub _cov_cell ($s, $uncompiled, $have_ppi, %opts) {
  no warnings "once";
  local %Devel::Cover::Report::Html_crisp::R = (have_ppi => $have_ppi);
  Devel::Cover::Report::Html_crisp::cov_cell(
    $s, $uncompiled, $opts{data_value}, $opts{link},
  )
}

sub test_cov_cell_tooltips () {
  my $covered
    = _cov_cell({ pc => "50.0", class => "c1", covered => 5, total => 10 }, 0,
      1);
  like $covered, qr/class="c1 tip-hover"/, "covered cell: tip-hover";
  like $covered, qr/glass-tip">5 \/ 10</,  "covered cell: glass-tip 5 / 10";

  my $na
    = _cov_cell({ pc => "n/a", class => "na", covered => 0, total => 0 }, 0, 1,
    );
  unlike $na, qr/tip-hover/,
    "tested n/a cell: no tip-hover (0/0 uninformative)";
  unlike $na, qr/glass-tip/,
    "tested n/a cell: no glass-tip (0/0 uninformative)";

  my $unc_ppi
    = _cov_cell({ pc => "0", class => "c0", covered => 0, total => 5 }, 1, 1);
  like $unc_ppi, qr/class="c0 tip-hover"/, "untested with PPI: tip-hover";
  like $unc_ppi, qr/glass-tip">0 \/ 5</,   "untested with PPI: glass-tip 0 / 5";

  my $unc_no_ppi
    = _cov_cell({ pc => "-", class => "na", covered => 0, total => 0 }, 1, 0);
  unlike $unc_no_ppi, qr/tip-hover/, "untested without PPI: no tip-hover class";
  unlike $unc_no_ppi, qr/glass-tip/, "untested without PPI: no glass-tip";
}

sub test_cov_cell_link () {
  my $no_link
    = _cov_cell({ pc => "75.0", class => "c2", covered => 3, total => 4 }, 0,
      1);
  unlike $no_link, qr/<a class="cell-link"/, "no link: no anchor";

  my $with_link = _cov_cell(
    { pc => "75.0", class => "c2", covered => 3, total => 4 },
    0, 1, link => "tests-foo.html#filter=condition",
  );
  like $with_link,
    qr{<a class="cell-link" href="tests-foo\.html#filter=condition">},
    "with link: anchor has correct href";
  like $with_link, qr/<a class="cell-link"[^>]*>75\.0/,
    "with link: anchor wraps the percent value";
}

sub test_slop_cell_link () {
  no warnings "once";
  local %Devel::Cover::Report::Html_crisp::R = ();

  my $f = {
    file_slop  => "33.4",
    file_crap  => "12.5",
    file_cc    => 5,
    file_cov   => 80,
    worst_subs => [],
  };

  my $no_link = Devel::Cover::Report::Html_crisp::slop_cell($f);
  unlike $no_link, qr/<a class="cell-link"/, "slop no link: no anchor";

  my $with_link
    = Devel::Cover::Report::Html_crisp::slop_cell($f, "tests-foo.html");
  like $with_link, qr{<a class="cell-link" href="tests-foo\.html">33\.4</a>},
    "slop with link: anchor wraps slop value (no filter hash)";
}

sub test_stat_badge_no_tip_when_empty () {
  no warnings "once";
  local %Devel::Cover::Report::Html_crisp::R = (
    full  => { statement => "Statement", total => "total" },
    short => { statement => "stmt",      total => "total" },
  );

  my $empty = Devel::Cover::Report::Html_crisp::stat_badge(
    "statement", { pc => "n/a", class => "na", covered => 0, total => 0 },
  );
  unlike $empty, qr/tip-hover/, "stat_badge: no tip-hover when total = 0";
  unlike $empty, qr/glass-tip/, "stat_badge: no glass-tip when total = 0";

  my $real = Devel::Cover::Report::Html_crisp::stat_badge(
    "statement", { pc => "75.0", class => "c2", covered => 3, total => 4 },
  );
  like $real, qr/tip-hover/,         "stat_badge: tip-hover when total > 0";
  like $real, qr{glass-tip">3 / 4<}, "stat_badge: glass-tip with counts";
}

sub test_index_filter_links () {
  my $got = $Golden{"coverage.html"};
  like $got, qr{cell-link" href="[^"]*#filter=statement"},
    "index: statement cell links with #filter=statement";
  like $got, qr{cell-link" href="[^"]*#filter=total"},
    "index: total cell links with #filter=total";
  like $got, qr{cell-link" href="[^"]*\.html">},
    "index: SLOP cell links to file without #filter";
}

sub test_dir_header_links () {
  my $got = $Golden{"coverage.html"};
  my ($dir_block) = $got =~ m{(<tr class="dir-header".*?</tr>)}s;
  ok defined $dir_block, "dir-header row found in golden index";
  like $dir_block, qr/cell-link/,
    "dir-header: cells wrapped in cell-link anchors";
  like $dir_block, qr/#filter=/,
    "dir-header: cell-link hrefs include filter hash";
}

sub test_app_js_hash_filter () {
  my $app_js = slurp(File::Spec->catfile($Outdir, "assets", "app.js"));
  like $app_js, qr/syncHash/,              "app.js: syncHash helper present";
  like $app_js, qr/history\.replaceState/, "app.js: uses replaceState";
  like $app_js, qr/#filter=/,              "app.js: filter hash referenced";
  like $app_js, qr/location\.hash/,        "app.js: reads location.hash";
  like $app_js, qr/cell-link/, "app.js: index click handler aware of cell-link";
}

sub test_untested_badge_tooltip () {
  no warnings "once";

  {
    local %Devel::Cover::Report::Html_crisp::R = (have_ppi => 1);
    my $got = Devel::Cover::Report::Html_crisp::untested_badge();
    unlike $got, qr/tip-hover/, "untested badge with PPI: no tip-hover";
    unlike $got, qr/glass-tip/, "untested badge with PPI: no glass-tip";
  }

  {
    local %Devel::Cover::Report::Html_crisp::R = (have_ppi => 0);
    my $got = Devel::Cover::Report::Html_crisp::untested_badge();
    like $got, qr/class="untested-badge tip-hover"/,
      "untested badge without PPI: tip-hover";
    like $got, qr/glass-tip">Install PPI for coverage estimates</,
      "untested badge without PPI: install-PPI tooltip";
  }
}

sub main () {
  _setup;
  ok keys %Golden > 0, "golden output captured";
  test_crit_name;
  test_render_layout;
  test_render_index;
  test_render_file_page;
  test_tooltip_structure;
  test_glass_tooltips;
  test_dir_row_slop;
  test_module_slop_badge;
  test_total_badge_filter;
  test_file_nav_keys;
  test_render_untested_page;
  test_cov_cell_tooltips;
  test_cov_cell_link;
  test_slop_cell_link;
  test_stat_badge_no_tip_when_empty;
  test_index_filter_links;
  test_dir_header_links;
  test_app_js_hash_filter;
  test_untested_badge_tooltip;
  done_testing;
}

main;

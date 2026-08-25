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
use List::Util qw( first );
use Test::More import =>
  [qw( diag done_testing is is_deeply isa_ok like ok plan skip )];
use Devel::Cover::Test::Showcase qw(
  create_cover_db
  run_cover
  setup_lib_dir
  slurp
);

eval "require JSON::MaybeXS; 1" or do {
  plan skip_all => "JSON::MaybeXS not available";
  exit;
};

sub markers_line ($libdir, $pattern) {
  my @lines = split /\n/, slurp("$libdir/Covered/Markers.pm");
  for my $i (0 .. $#lines) {
    return $i + 1 if $lines[$i] =~ $pattern;
  }
  die "No line matching $pattern in Covered/Markers.pm";
}

sub markers_entry ($json) {
  my $path = first { /Covered\W+Markers\.pm$/ } keys $json->{files}->%*;
  ($path, $path ? $json->{files}{$path} : undef)
}

sub json_report ($tmpdir, $libdir, $cover_db, $subdir, @extra) {
  my $outdir = File::Spec->catdir($tmpdir, $subdir);
  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "json",
    "--outputdir",  $outdir, "--silent", @extra,
    $cover_db,
  );
  is $exit, 0, "cover --report json exits 0 ($subdir)" or diag $out;
  my $path = File::Spec->catfile($outdir, "cover.json");
  ok -e $path, "cover.json was generated ($subdir)";
  JSON::MaybeXS->new(utf8 => 1)->decode(slurp($path))
}

# The new `json` report emits full per-line detail (statements, branches,
# conditions, condition_truth_tables, mcdc, subroutines, pod) plus per-file
# meta and a top-level devel_cover_version.  It is the supersedes-everything
# feed requested in GH-418.
sub test_json_detailed_report ($json) {
  # Top-level structure.
  like $json->{devel_cover_version}, qr/^\d+\.\d+/,
    "devel_cover_version looks like a version number";
  isa_ok $json->{runs},    "ARRAY", "runs";
  isa_ok $json->{summary}, "HASH",  "summary";
  ok exists $json->{summary}{Total}, "summary has Total";
  isa_ok $json->{files}, "HASH", "files";
  ok scalar(keys $json->{files}->%*) >= 1, "at least one file recorded";

  # Pick the Covered::Calc.pm entry - it has the richest mix of criteria.
  my $calc_path = first { /Covered\W+Calc\.pm$/ } keys $json->{files}->%*;
  ok $calc_path, "found Covered/Calc.pm in files"
    or do { done_testing; return };
  my $f = $json->{files}{$calc_path};

  # meta is always present and has the documented keys.
  isa_ok $f->{meta}, "HASH", "Calc.pm meta";
  ok exists $f->{meta}{uncompiled}, "meta has uncompiled";
  ok exists $f->{meta}{digest},     "meta has digest";
  ok exists $f->{meta}{counts},     "meta has counts";
  is $f->{meta}{uncompiled}, 0, "Calc.pm is compiled (uncompiled = 0)";
  like $f->{meta}{digest}, qr/^[0-9a-f]+$/i, "digest is hex";

  # Per-criterion sections.
  isa_ok $f->{statements},             "HASH", "statements";
  isa_ok $f->{branches},               "HASH", "branches";
  isa_ok $f->{conditions},             "HASH", "conditions";
  isa_ok $f->{condition_truth_tables}, "HASH", "condition_truth_tables";
  isa_ok $f->{mcdc},                   "HASH", "mcdc";
  isa_ok $f->{subroutines},            "HASH", "subroutines";

  # At least one statement was actually covered.
  my $covered_stmt = first { $_->{covered} > 0 }
    map { $f->{statements}{$_}->@* } keys $f->{statements}->%*;
  ok $covered_stmt, "at least one statement has covered > 0";

  # Branch entries match the documented structure.
  my $first_branch_line = (sort { $a <=> $b } keys $f->{branches}->%*)[0];
  ok defined $first_branch_line, "branches has at least one line";
  my $branch = $f->{branches}{$first_branch_line}[0];
  ok defined $branch->{text}, "branch has text";
  isa_ok $branch->{covered},     "ARRAY", "branch covered";
  isa_ok $branch->{uncoverable}, "ARRAY", "branch uncoverable";
  is $branch->{covered}->@*, $branch->{uncoverable}->@*,
    "covered and uncoverable arrays have matching length";

  # Truth tables: Calc.pm has `$x && $y` in sub check.  Even when not
  # exercised the truth table is generated (with covered: 0 rows).
  my $tt_line = first { $f->{condition_truth_tables}{$_}->@* }
    keys $f->{condition_truth_tables}->%*;
  ok $tt_line, "at least one line has a truth table"
    or do { done_testing; return };
  my $tt = $f->{condition_truth_tables}{$tt_line}[0];
  ok defined $tt->{expr},       "truth table has expr";
  ok defined $tt->{percentage}, "truth table has percentage";
  isa_ok $tt->{rows}, "ARRAY", "truth table rows";
  ok $tt->{rows}->@* >= 1, "truth table has at least one row";
  my $row = $tt->{rows}[0];
  isa_ok $row->{inputs}, "ARRAY", "row inputs";
  ok defined $row->{result},  "row has result";
  ok defined $row->{covered}, "row has covered";

  # MC/DC: Calc.pm has `$x && $y` in sub check.  The analyser produces a
  # per-decision record with text, labels, covered (per-column 1/0), and
  # error.
  my $mcdc_line = first { $f->{mcdc}{$_}->@* } keys $f->{mcdc}->%*;
  ok $mcdc_line, "at least one line has mcdc data"
    or do { done_testing; return };
  my $m = $f->{mcdc}{$mcdc_line}[0];
  ok defined $m->{text}, "mcdc has text";
  isa_ok $m->{labels},  "ARRAY", "mcdc labels";
  isa_ok $m->{covered}, "ARRAY", "mcdc covered";
  is $m->{labels}->@*, $m->{covered}->@*,
    "labels and covered arrays have matching length";
  isa_ok $m->{uncoverable}, "ARRAY", "mcdc uncoverable";
  is $m->{uncoverable}->@*, $m->{covered}->@*,
    "mcdc covered and uncoverable arrays have matching length";
  ok defined $m->{error}, "mcdc has error";
}

# Excused and stale markers must be distinguishable in the output
sub test_uncoverable_states ($json, $libdir) {
  my ($path, $f) = markers_entry($json);
  ok $path, "found Covered/Markers.pm in files" or return;

  my $excused = markers_line($libdir, qr/die "emergency stop"/);
  my $stale   = markers_line($libdir, qr/return "still called"/);

  my $e = $f->{statements}{$excused}[0];
  is $e->{covered},     0, "excused statement is not covered";
  is $e->{uncoverable}, 1, "excused statement is marked uncoverable";
  is $e->{error},       0, "excused statement is not an error";

  my $s = $f->{statements}{$stale}[0];
  ok $s->{covered} > 0, "stale-marked statement ran";
  is $s->{uncoverable}, 1, "stale-marked statement keeps its marker";
  is $s->{error},       1, "stale-marked statement is an error";
}

# Truth table rows carry the uncoverable flag and an error-based percentage
sub test_truth_table_uncoverable ($json, $libdir) {
  my ($path, $f) = markers_entry($json);
  ok $path, "found Covered/Markers.pm in files" or return;

  my $audit = markers_line($libdir, qr/my \$ok = \$active && \$value/);
  my $tt    = ($f->{condition_truth_tables}{$audit} // [])->[0];
  ok $tt, "audit line has a truth table" or return;

  ok defined $_->{uncoverable}, "row has uncoverable flag" for $tt->{rows}->@*;
  my $excused_row
    = first { $_->{uncoverable} && !$_->{covered} } $tt->{rows}->@*;
  ok $excused_row, "the excused outcome's row is flagged uncoverable";
  is $tt->{percentage}, 100, "excused row does not drag the percentage down";
}

# The error rule must be recorded so consumers can interpret `error`
sub test_error_rule_recorded ($json, $json_ignore, $libdir) {
  is $json->{ignore_covered_err}, 0, "error rule recorded (default off)";
  is $json_ignore->{ignore_covered_err}, 1,
    "error rule recorded (-ignore_covered_err)";

  my (undef, $f) = markers_entry($json_ignore);
  my $stale = markers_line($libdir, qr/return "still called"/);
  my $s     = $f->{statements}{$stale}[0];
  is $s->{error}, 0, "stale marker is forgiven under -ignore_covered_err";
}

# Phase 0 made pod aggregate uncoverable like every other criterion
sub test_summary_pod_uncoverable ($json) {
  SKIP: {
    skip "Pod::Coverage not available", 1
      unless eval { require Pod::Coverage; 1 };
    ok exists $json->{summary}{Total}{pod}{uncoverable},
      "summary Total pod has an uncoverable count";
  }
}

# json_summary should NOT have a files key - this protects against accidental
# divergence in future where one reporter's output drifts into the other.
sub test_summary_and_detailed_distinct ($tmpdir, $libdir, $cover_db) {
  my $outdir = File::Spec->catdir($tmpdir, "json_summary");

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "json_summary",
    "--outputdir",  $outdir, "--silent", $cover_db,
  );
  is $exit, 0, "json_summary exits 0" or diag $out;

  my $summary = JSON::MaybeXS->new(utf8 => 1)
    ->decode(slurp(File::Spec->catfile($outdir, "cover.json")));

  ok !exists $summary->{files}, "json_summary lacks files key";
  ok !exists $summary->{devel_cover_version},
    "json_summary lacks devel_cover_version";
}

# The summary must cover only the selected files, not the whole database
sub test_summary_restricted ($tmpdir, $libdir, $cover_db) {
  my $outdir = File::Spec->catdir($tmpdir, "json_select");
  my ($out, $exit) = run_cover(
    "--select_re", '/Covered.Trivial.pm$',
    "--report",    "json",
    "--outputdir", $outdir,
    "--silent",    $cover_db,
  );
  is $exit, 0, "cover --select_re --report json exits 0" or diag $out;
  my $json = JSON::MaybeXS->new(utf8 => 1)
    ->decode(slurp(File::Spec->catfile($outdir, "cover.json")));
  is keys $json->{files}->%*, 1, "one file selected";
  is_deeply [sort keys $json->{summary}->%*],
    [sort "Total", keys $json->{files}->%*],
    "summary keys are the files keys plus Total";
}

# A report after json in the same run must keep the restricted summary
sub test_summary_isolated ($tmpdir, $libdir, $cover_db) {
  my @select = (
    "--select_re", '/Covered.Trivial.pm$',
    "--select_re", '/Covered.Utils.pm$',
  );
  my $outdir = File::Spec->catdir($tmpdir, "json_text");
  my ($text_only)
    = run_cover(@select, "--report", "text", "--silent", $cover_db);
  my ($combined) = run_cover(
    @select, "--report",    "json",  "--report",
    "text",  "--outputdir", $outdir, "--silent",
    $cover_db,
  );
  my $banner = sub ($out) { ($out =~ /(Module Summary\n-+\n\n.*?\n\n)/s)[0] };

  ok defined $banner->($text_only), "text-only run prints a Module Summary";
  is $banner->($combined), $banner->($text_only),
    "text Module Summary unchanged after a json report";
}

sub main () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);

  my $json        = json_report($tmpdir, $libdir, $cover_db, "json");
  my $json_ignore = json_report(
    $tmpdir, $libdir, $cover_db, "json_ignore", "-ignore_covered_err",
  );

  test_json_detailed_report($json);
  test_uncoverable_states($json, $libdir);
  test_truth_table_uncoverable($json, $libdir);
  test_error_rule_recorded($json, $json_ignore, $libdir);
  test_summary_pod_uncoverable($json);
  test_summary_and_detailed_distinct($tmpdir, $libdir, $cover_db);
  test_summary_restricted($tmpdir, $libdir, $cover_db);
  test_summary_isolated($tmpdir, $libdir, $cover_db);
  done_testing;
}

main;

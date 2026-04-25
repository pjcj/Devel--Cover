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
use Test::More import => [qw( diag done_testing is isa_ok like ok plan )];
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

# The new `json` report emits full per-line detail (statements, branches,
# conditions, condition_truth_tables, subroutines, pod) plus per-file meta
# and a top-level devel_cover_version.  It is the supersedes-everything feed
# requested in GH-418.
sub test_json_detailed_report () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);
  my $outdir   = File::Spec->catdir($tmpdir, "json");

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "json",
    "--outputdir",  $outdir, "--silent", $cover_db,
  );

  is $exit, 0, "cover --report json exits 0" or diag $out;

  my $path = File::Spec->catfile($outdir, "cover.json");
  ok -e $path, "cover.json was generated";

  my $json = JSON::MaybeXS->new(utf8 => 1)->decode(slurp($path));

  # Top-level shape.
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
  isa_ok $f->{subroutines},            "HASH", "subroutines";

  # At least one statement was actually covered.
  my $covered_stmt = first { $_->{covered} > 0 }
    map { $f->{statements}{$_}->@* } keys $f->{statements}->%*;
  ok $covered_stmt, "at least one statement has covered > 0";

  # Branch entries match the documented shape.
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
}

# json_summary should NOT have a files key - this protects against accidental
# divergence in future where one reporter's output drifts into the other.
sub test_summary_and_detailed_distinct () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);
  my $outdir   = File::Spec->catdir($tmpdir, "json2");

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

sub main () {
  test_json_detailed_report;
  test_summary_and_detailed_distinct;
  done_testing;
}

main;

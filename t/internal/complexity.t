#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Cwd     ();
use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Digest::MD5 ();
use File::Spec  ();
use File::Temp  qw( tempdir );
use Test::More import => [qw( done_testing is like ok )];

my $Root = Cwd::cwd();

use Devel::Cover::DB            ();
use Devel::Cover::DB::Structure ();
use Devel::Cover::Report::Text  ();

my $Tmpdir = tempdir(CLEANUP => 1);

sub md5_file ($path) {
  open my $fh, "<", $path or die "Cannot open $path: $!";
  binmode $fh;
  Digest::MD5->new->addfile($fh)->hexdigest
}

# Run a script under Devel::Cover and return ($db_path, $script_path).
sub run_cover ($label, $script_content) {
  my $script = File::Spec->catfile($Tmpdir, "$label.pl");
  my $db     = File::Spec->catdir($Tmpdir, "${label}_db");

  open my $fh, ">", $script or die "Cannot write $script: $!";
  print $fh $script_content;
  close $fh or die "Cannot close $script: $!";

  my @inc = map { "-I$_" } "$Root/blib/arch", "$Root/blib/lib", "$Root/lib";

  system($^X, @inc, "-MDevel::Cover=-db,$db,-silent,1", $script) == 0
    or die "Failed to run $label under Devel::Cover: $?";

  ($db, $script)
}

# Run a script under Devel::Cover and return the complexity hash for that
# script's file digest.
sub cover_complexity ($label, $script_content) {
  my ($db, $script) = run_cover($label, $script_content);
  my $st = Devel::Cover::DB::Structure->new(base => $db);
  $st->read_all;
  $st->get_complexity(md5_file($script))
}

# Line numbers matter - they are the hash keys for complexity lookup.
# If you change the layout, update the assertions below.
#
# Line 1: use strict;
# Line 2: use warnings;
# Line 3: (blank)
# Line 4: sub linear       - no decisions
# Line 5: sub one_if       - one cond_expr (if)
# Line 6: sub elsif_two    - two cond_exprs (if + elsif)
# Line 7: sub with_and     - one logop (&&)
# Line 8: sub ternary      - one cond_expr (?:)
# Line 9: sub with_foreach - one foreach loop (iter)

my $Cc_script = <<'PERL';
use strict;
use warnings;

sub linear       { 42 }
sub one_if       { if ($_[0]) { return 1 } return 0 }
sub elsif_two    { if ($_[0] > 0) { 1 } elsif ($_[0] < 0) { -1 } else { 0 } }
sub with_and     { $_[0] && $_[1] }
sub ternary      { $_[0] ? 1 : 0 }
sub with_foreach { my $s; foreach my $x (@_) { $s .= $x } $s }

linear();
one_if(1);
elsif_two(1);
with_and(1, 1);
ternary(1);
with_foreach("a", "b");
PERL

# Signature script for testing argdefelem CC counting.
# Line numbers:
# 1: use 5.20.0;
# 2: use warnings;
# 3: use feature "signatures";
# 4: no warnings "experimental::signatures";
# 5: (blank)
# 6: sub with_default         - CC=2: 1 argdefelem
# 7: sub with_default_cond    - CC=3: 1 argdefelem + 1 logop (||)
# 8: (blank)
# 9: with_default();
# 10: with_default_cond();

my $Sig_script = <<'PERL';
use 5.20.0;
use warnings;
use feature "signatures";
no warnings "experimental::signatures";

sub with_default ($x = 42) { $x }
sub with_default_cond ($x = $ENV{X} || 1) { $x }

with_default();
with_default_cond();
PERL

# CRAP scoring test script.
# Line layout:
# 1: use strict;
# 2: use warnings;
# 3: (blank)
# 4: sub fully_covered     - CC=1, all stmts executed
# 5: sub uncalled           - CC=1, no stmts executed
# 6: sub partial_branch {   - CC=2, only true branch taken
# 7:     if ($_[0]) { return 1 }
# 8:     return 0;
# 9: }
# 10: (blank)
# 11: fully_covered();
# 12: partial_branch(1);

my $Crap_script = <<'PERL';
use strict;
use warnings;

sub fully_covered { 42 }
sub uncalled      { 42 }
sub partial_branch {
    if ($_[0]) { return 1 }
    return 0;
}

fully_covered();
partial_branch(1);
PERL

sub test_cc_counting () {
  my $cc = cover_complexity("cc_basic", $Cc_script);

  ok defined $cc, "complexity data present in structure";

  is $cc->{4}{linear}[0],       1, "linear: CC = 1";
  is $cc->{5}{one_if}[0],       2, "one if: CC = 2";
  is $cc->{6}{elsif_two}[0],    3, "if/elsif: CC = 3";
  is $cc->{7}{with_and}[0],     2, "&&: CC = 2";
  is $cc->{8}{ternary}[0],      2, "ternary: CC = 2";
  is $cc->{9}{with_foreach}[0], 2, "foreach: CC = 2";
}

# Summary aggregation tests
# Reuse the same test script layout (6 subs: CC = 1, 2, 3, 2, 2, 2).
sub test_summary_aggregation () {
  my ($db_path, $script) = run_cover("cc_summary", $Cc_script);

  my $st = Devel::Cover::DB::Structure->new(base => $db_path);
  $st->read_all;

  my $db = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  $db->set_structure($st);
  $db->calculate_summary(statement => 1, subroutine => 1);

  # Find the cover file key for our script
  my ($file) = grep /cc_summary\.pl$/, keys $db->{summary}->%*;
  ok defined $file, "summary contains cover file for test script";

  my $cs = $db->{summary}{$file}{complexity};
  ok defined $cs, "file summary has complexity entry";

  # 8 subs: 6 named + 2 BEGIN blocks from use strict/warnings.
  # CC values: 1,1 (BEGINs), 1,2,3,2,2,2 (named) = sum 14, mean 1.75
  is $cs->{max},   3,    "file complexity max = 3 (elsif_two)";
  is $cs->{mean},  1.75, "file complexity mean = 1.75";
  is $cs->{count}, 8,    "file complexity count = 8 subs";

  my $ts = $db->{summary}{Total}{complexity};
  ok defined $ts, "Total summary has complexity entry";

  is $ts->{max},   3,    "Total complexity max = 3";
  is $ts->{mean},  1.75, "Total complexity mean = 1.75";
  is $ts->{count}, 8,    "Total complexity count = 8";
}

# Sub end line tests
# Uses a multi-line sub to verify end_line > start_line.
# Subs are keyed by first statement line (not the sub declaration).
# Line layout:
# 1: use strict;
# 2: use warnings;
# 3: (blank)
# 4: sub oneliner { 42 }         - first stmt on line 4
# 5: sub multiline {
# 6:   my $x = 1;                - first stmt on line 6
# 7:   my $y = 2;
# 8:   $x + $y;                  - last stmt on line 8
# 9: }
# 10: (blank)
# 11: oneliner();
# 12: multiline();
sub test_end_lines () {
  my ($db_path, $script) = run_cover("cc_endline", <<'PERL');
use strict;
use warnings;

sub oneliner { 42 }
sub multiline {
  my $x = 1;
  my $y = 2;
  $x + $y;
}

oneliner();
multiline();
PERL

  my $st = Devel::Cover::DB::Structure->new(base => $db_path);
  $st->read_all;

  my $ends = $st->get_end_lines(md5_file($script));
  ok defined $ends, "end_lines data present in structure";

  is $ends->{4}{oneliner}[0], 4, "single-line sub: end_line = start_line";
  is $ends->{6}{multiline}[0], 8,
    "multi-line sub: end_line = last statement line";
}

# Signature default CC tests.
# Verifies argdefelem ops count as CC decision points, and that
# conditions inside defaults (logops, cond_exprs) stack correctly.
sub test_signature_cc () {
  my $cc = cover_complexity("cc_sig", $Sig_script);

  ok defined $cc, "signature: complexity data present";

  is $cc->{6}{with_default}[0], 2, "signature default: CC = 2 (1 argdefelem)";
  is $cc->{7}{with_default_cond}[0], 3,
    "signature default with ||: CC = 3 (1 argdefelem + 1 logop)";
}

# CRAP (Change Risk Anti-Patterns) scoring tests.
# Verifies that summarise_complexity computes per-sub combined
# coverage and CRAP scores alongside existing complexity aggregation.
sub test_slop_scoring () {
  my ($db_path, $script) = run_cover("cc_crap", $Crap_script);

  my $st = Devel::Cover::DB::Structure->new(base => $db_path);
  $st->read_all;

  my $db = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  $db->set_structure($st);
  $db->calculate_summary(
    statement  => 1,
    branch     => 1,
    condition  => 1,
    subroutine => 1,
  );

  my ($file) = grep /cc_crap\.pl$/, keys $db->{summary}->%*;
  ok defined $file, "slop: summary contains cover file";

  my $slop = $db->{summary}{$file}{slop};
  ok defined $slop, "slop: file summary has slop entry";

  ok exists $slop->{max},   "slop: has max";
  ok exists $slop->{mean},  "slop: has mean";
  ok exists $slop->{count}, "slop: has count";
  ok exists $slop->{subs},  "slop: has subs";

  # Build lookup by sub name for easier assertions.
  my %by_name = map { $_->{name} => $_ } $slop->{subs}->@*;

  # fully_covered: CC=1, cov=100%, CRAP = 1^2*(1-1)^3 + 1 = 1
  my $fc = $by_name{fully_covered};
  ok defined $fc, "slop: fully_covered present";
  is $fc->{cc},   1,   "slop: fully_covered CC = 1";
  is $fc->{cov},  100, "slop: fully_covered cov = 100";
  is $fc->{crap}, 1,   "slop: fully_covered CRAP = 1";
  is $fc->{slop}, 0,   "slop: fully_covered SLOP = 0";

  # uncalled: CC=1, cov=0%, CRAP = 1^2*(1-0)^3 + 1 = 2
  my $uc = $by_name{uncalled};
  ok defined $uc, "slop: uncalled present";
  is $uc->{cc},   1, "slop: uncalled CC = 1";
  is $uc->{cov},  0, "slop: uncalled cov = 0";
  is $uc->{crap}, 2, "slop: uncalled CRAP = 2";
  ok abs($uc->{slop} - log(2) * 10) < 0.01, "slop: uncalled SLOP = ln(2)*10";

  # partial_branch: CC=2, partial coverage.
  # Bounds: cov=100% => CRAP=2, cov=0% => CRAP=6.
  my $pb = $by_name{partial_branch};
  ok defined $pb, "slop: partial_branch present";
  is $pb->{cc}, 2, "slop: partial_branch CC = 2";
  ok $pb->{crap} > 2,           "slop: partial_branch CRAP > CC";
  ok $pb->{crap} < 6,           "slop: partial_branch CRAP < CC^2+CC";
  ok $pb->{slop} > 0,           "slop: partial_branch SLOP > 0";
  ok $pb->{slop} > $uc->{slop}, "slop: partial_branch SLOP > uncalled SLOP";

  # Total aggregation
  my $ts = $db->{summary}{Total}{slop};
  ok defined $ts,         "slop: Total has slop entry";
  ok exists $ts->{max},   "slop: Total has max";
  ok exists $ts->{mean},  "slop: Total has mean";
  ok exists $ts->{count}, "slop: Total has count";
}

# Text report CC/SLOP column tests.
# Verifies that print_subroutines includes CC and SLOP columns
# when CRAP summary data is available.
sub test_text_report_slop () {
  my ($db_path, $script) = run_cover("cc_text", $Crap_script);

  my $st = Devel::Cover::DB::Structure->new(base => $db_path);
  $st->read_all;

  my $db = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  $db->set_structure($st);
  $db->calculate_summary(
    statement  => 1,
    branch     => 1,
    condition  => 1,
    subroutine => 1,
  );

  my @files = $db->cover->items;
  my $options
    = { show => { subroutine => 1 }, file => \@files, annotations => [] };

  # Capture the report output.
  my $output;
  {
    open my $fh, ">", \$output or die "Cannot open scalar ref: $!";
    local *STDOUT = $fh;
    Devel::Cover::Report::Text->report($db, $options);
    close $fh or die "Cannot close scalar ref: $!";
  }

  # Header should contain CC and SLOP columns.
  like $output, qr/^\s*Subroutine\b.*\bCC\b.*\bSLOP\b/m,
    "text: header contains CC and SLOP columns";

  # fully_covered: CC=1, SLOP=0.0 (CRAP=1, ln(1)*10=0)
  like $output, qr/fully_covered\s+\d+\s+1\s+0\.0\b/,
    "text: fully_covered has CC=1 SLOP=0.0";

  # uncalled: CC=1, SLOP=6.9 (CRAP=2, ln(2)*10=6.93)
  like $output, qr/uncalled\s+\d+\s+1\s+6\.9\b/,
    "text: uncalled has CC=1 SLOP=6.9";

  # partial_branch: CC=2, SLOP > 6.9
  like $output, qr/partial_branch\s+\d+\s+2\s+\d+\.\d/,
    "text: partial_branch has CC=2 and a SLOP score";
}

# File-level CRAP tests.
# Verifies that summarise_complexity computes file_cc, file_cov,
# and file_crap by treating the entire file as one sub body.
sub test_file_level_slop () {
  my ($db_path, $script) = run_cover("cc_filecrap", $Crap_script);

  my $st = Devel::Cover::DB::Structure->new(base => $db_path);
  $st->read_all;

  my $db = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  $db->set_structure($st);
  $db->calculate_summary(
    statement  => 1,
    branch     => 1,
    condition  => 1,
    subroutine => 1,
  );

  my ($file) = grep /cc_filecrap\.pl$/, keys $db->{summary}->%*;
  ok defined $file, "fileslop: summary contains cover file";

  my $slop = $db->{summary}{$file}{slop};
  ok defined $slop, "fileslop: file summary has slop entry";

  # file_cc = sum of per-sub CCs - count + 1
  ok exists $slop->{file_cc}, "fileslop: has file_cc";
  my $expected_cc_sum = 0;
  $expected_cc_sum += $_->{cc} for $slop->{subs}->@*;
  is $slop->{file_cc}, $expected_cc_sum - $slop->{count} + 1,
    "fileslop: file_cc = sum(cc) - count + 1";

  # file_cov: combined stmt+branch+condition coverage
  ok exists $slop->{file_cov}, "fileslop: has file_cov";
  ok $slop->{file_cov} >= 0 && $slop->{file_cov} <= 100,
    "fileslop: file_cov is 0..100";

  # file_crap: CRAP formula applied to file-level inputs
  ok exists $slop->{file_crap}, "fileslop: has file_crap";
  my $cc            = $slop->{file_cc};
  my $cov           = $slop->{file_cov};
  my $expected_crap = $cc**2 * (1 - $cov / 100)**3 + $cc;
  is $slop->{file_crap}, $expected_crap,
    "fileslop: file_crap matches CRAP formula";

  # file_slop: ln(file_crap) * 10
  ok exists $slop->{file_slop}, "fileslop: has file_slop";
  my $expected_slop = $slop->{file_crap} > 1 ? log($slop->{file_crap}) * 10 : 0;
  ok abs($slop->{file_slop} - $expected_slop) < 0.01,
    "fileslop: file_slop = log(file_crap) * 10";

  # Total aggregation
  my $ts = $db->{summary}{Total}{slop};
  ok defined $ts,             "fileslop: Total has slop entry";
  ok exists $ts->{file_crap}, "fileslop: Total has file_crap";
  ok exists $ts->{file_slop}, "fileslop: Total has file_slop";

  # Module-level SLOP (whole-codebase CRAP)
  ok exists $ts->{module_cc},   "fileslop: Total has module_cc";
  ok exists $ts->{module_cov},  "fileslop: Total has module_cov";
  ok exists $ts->{module_crap}, "fileslop: Total has module_crap";
  ok exists $ts->{module_slop}, "fileslop: Total has module_slop";
  ok $ts->{module_cc} > 0,      "fileslop: module_cc > 0";
  my $mcc = $ts->{module_cc};
  my $mcv = $ts->{module_cov};
  my $expected_mcrap = $mcc**2 * (1 - $mcv / 100)**3 + $mcc;
  is $ts->{module_crap}, $expected_mcrap,
    "fileslop: module_crap matches CRAP formula";
  my $expected_mslop
    = $ts->{module_crap} > 1 ? log($ts->{module_crap}) * 10 : 0;
  ok abs($ts->{module_slop} - $expected_mslop) < 0.01,
    "fileslop: module_slop = log(module_crap) * 10";
}

sub test_dir_level_slop () {
  my ($db_path, $script) = run_cover("cc_dirslop", $Crap_script);

  my $st = Devel::Cover::DB::Structure->new(base => $db_path);
  $st->read_all;

  my $db = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  $db->set_structure($st);
  $db->calculate_summary(
    statement  => 1,
    branch     => 1,
    condition  => 1,
    subroutine => 1,
  );

  # Directory summary should exist for the script's parent dir
  my ($file) = grep /cc_dirslop\.pl$/, keys $db->{summary}->%*;
  ok defined $file, "dirslop: file found in summary";
  (my $dir = $file) =~ s|/[^/]+$||;
  my $ds = $db->dir_summary($dir);
  ok defined $ds, "dirslop: dir summary exists";

  # Per-criterion aggregation
  for my $c (qw( statement branch condition total )) {
    ok exists $ds->{$c},           "dirslop: has $c";
    ok defined $ds->{$c}{covered}, "dirslop: $c has covered";
    ok defined $ds->{$c}{total},   "dirslop: $c has total";
  }

  # SLOP entry
  my $slop = $ds->{slop};
  ok defined $slop,             "dirslop: has slop entry";
  ok exists $slop->{file_cc},   "dirslop: has file_cc";
  ok exists $slop->{file_cov},  "dirslop: has file_cov";
  ok exists $slop->{file_crap}, "dirslop: has file_crap";
  ok exists $slop->{file_slop}, "dirslop: has file_slop";

  # dir_cc should equal the single file's file_cc (one file
  # in the directory)
  my $file_slop = $db->{summary}{$file}{slop};
  is $slop->{file_cc}, $file_slop->{file_cc},
    "dirslop: dir cc matches single file cc";

  # CRAP formula
  my $cc            = $slop->{file_cc};
  my $cov           = $slop->{file_cov};
  my $expected_crap = $cc**2 * (1 - $cov / 100)**3 + $cc;
  is $slop->{file_crap}, $expected_crap,
    "dirslop: dir crap matches CRAP formula";
}

sub main () {
  test_cc_counting;
  test_summary_aggregation;
  test_end_lines;
  test_signature_cc;
  test_slop_scoring;
  test_text_report_slop;
  test_file_level_slop;
  test_dir_level_slop;
}

main;
done_testing;

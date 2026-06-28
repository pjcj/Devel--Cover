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
use Test::More import => [qw( done_testing is like ok unlike )];

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
# Verifies argdefelem ops count as CC decision points, and that conditions
# inside defaults (logops, cond_exprs) stack correctly. Before 5.26, signatures
# compiled into cond_expr + or guard ops rather than a single argdefelem, adding
# an extra decision point.
sub test_signature_cc () {
  my $cc = cover_complexity("cc_sig", $Sig_script);

  ok defined $cc, "signature: complexity data present";

  my $extra = $] < 5.026 ? 1 : 0;
  is $cc->{6}{with_default}[0], 2 + $extra,
    "signature default: CC = " . (2 + $extra);
  is $cc->{7}{with_default_cond}[0], 3 + $extra,
    "signature default with ||: CC = " . (3 + $extra);
}

# CRAP (Change Risk Anti-Patterns) scoring tests.
# Verifies that summarise_complexity computes per-sub combined coverage and CRAP
# scores alongside existing complexity aggregation.
sub test_scar_scoring () {
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
  ok defined $file, "scar: summary contains cover file";

  my $scar = $db->{summary}{$file}{scar};
  ok defined $scar, "scar: file summary has scar entry";

  ok exists $scar->{max},   "scar: has max";
  ok exists $scar->{mean},  "scar: has mean";
  ok exists $scar->{count}, "scar: has count";
  ok exists $scar->{subs},  "scar: has subs";

  # Build lookup by sub name for easier assertions.
  my %by_name = map { $_->{name} => $_ } $scar->{subs}->@*;

  # fully_covered: CC=1, cov=100%, CRAP = 1^2*(1-1)^3 + 1 = 1
  my $fc = $by_name{fully_covered};
  ok defined $fc, "scar: fully_covered present";
  is $fc->{cc},   1,   "scar: fully_covered CC = 1";
  is $fc->{cov},  100, "scar: fully_covered cov = 100";
  is $fc->{crap}, 1,   "scar: fully_covered CRAP = 1";
  is $fc->{scar}, 0,   "scar: fully_covered SCAR = 0";

  # uncalled: CC=1, cov=0%, CRAP = 1^2*(1-0)^3 + 1 = 2
  my $uc = $by_name{uncalled};
  ok defined $uc, "scar: uncalled present";
  is $uc->{cc},   1, "scar: uncalled CC = 1";
  is $uc->{cov},  0, "scar: uncalled cov = 0";
  is $uc->{crap}, 2, "scar: uncalled CRAP = 2";
  ok abs($uc->{scar} - log(2) * 10) < 0.01, "scar: uncalled SCAR = ln(2)*10";

  # partial_branch: CC=2, partial coverage.
  # Bounds: cov=100% => CRAP=2, cov=0% => CRAP=6.
  my $pb = $by_name{partial_branch};
  ok defined $pb, "scar: partial_branch present";
  is $pb->{cc}, 2, "scar: partial_branch CC = 2";
  ok $pb->{crap} > 2,           "scar: partial_branch CRAP > CC";
  ok $pb->{crap} < 6,           "scar: partial_branch CRAP < CC^2+CC";
  ok $pb->{scar} > 0,           "scar: partial_branch SCAR > 0";
  ok $pb->{scar} > $uc->{scar}, "scar: partial_branch SCAR > uncalled SCAR";

  # Total aggregation
  my $ts = $db->{summary}{Total}{scar};
  ok defined $ts,         "scar: Total has scar entry";
  ok exists $ts->{max},   "scar: Total has max";
  ok exists $ts->{mean},  "scar: Total has mean";
  ok exists $ts->{count}, "scar: Total has count";
}

# Text report CC/SCAR column tests.
# Verifies that print_subroutines includes CC and SCAR columns
# when CRAP summary data is available.
sub test_text_report_scar () {
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

  # Header should contain CC and SCAR columns.
  like $output, qr/^\s*Subroutine\b.*\bCC\b.*\bSCAR\b/m,
    "text: header contains CC and SCAR columns";

  # fully_covered: CC=1, SCAR=0.0 (CRAP=1, ln(1)*10=0)
  like $output, qr/fully_covered\s+\d+\s+1\s+0\.0\b/,
    "text: fully_covered has CC=1 SCAR=0.0";

  # uncalled: CC=1, SCAR=6.9 (CRAP=2, ln(2)*10=6.93)
  like $output, qr/uncalled\s+\d+\s+1\s+6\.9\b/,
    "text: uncalled has CC=1 SCAR=6.9";

  # partial_branch: CC=2, SCAR > 6.9
  like $output, qr/partial_branch\s+\d+\s+2\s+\d+\.\d/,
    "text: partial_branch has CC=2 and a SCAR score";
}

# File-level CRAP tests.
# Verifies that summarise_complexity computes file_cc, file_cov,
# and file_crap by treating the entire file as one sub body.
sub test_file_level_scar () {
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
  ok defined $file, "filescar: summary contains cover file";

  my $scar = $db->{summary}{$file}{scar};
  ok defined $scar, "filescar: file summary has scar entry";

  # file_cc = sum of per-sub CCs - count + 1
  ok exists $scar->{file_cc}, "filescar: has file_cc";
  my $expected_cc_sum = 0;
  $expected_cc_sum += $_->{cc} for $scar->{subs}->@*;
  is $scar->{file_cc}, $expected_cc_sum - $scar->{count} + 1,
    "filescar: file_cc = sum(cc) - count + 1";

  # file_cov: combined stmt+branch+condition coverage
  ok exists $scar->{file_cov}, "filescar: has file_cov";
  ok $scar->{file_cov} >= 0 && $scar->{file_cov} <= 100,
    "filescar: file_cov is 0..100";

  # file_crap: CRAP formula applied to file-level inputs
  ok exists $scar->{file_crap}, "filescar: has file_crap";
  my $cc            = $scar->{file_cc};
  my $cov           = $scar->{file_cov};
  my $expected_crap = $cc**2 * (1 - $cov / 100)**3 + $cc;
  is $scar->{file_crap}, $expected_crap,
    "filescar: file_crap matches CRAP formula";

  # file_scar: ln(file_crap) * 10
  ok exists $scar->{file_scar}, "filescar: has file_scar";
  my $expected_scar = $scar->{file_crap} > 1 ? log($scar->{file_crap}) * 10 : 0;
  ok abs($scar->{file_scar} - $expected_scar) < 0.01,
    "filescar: file_scar = log(file_crap) * 10";

  # Total aggregation
  my $ts = $db->{summary}{Total}{scar};
  ok defined $ts,             "filescar: Total has scar entry";
  ok exists $ts->{file_crap}, "filescar: Total has file_crap";
  ok exists $ts->{file_scar}, "filescar: Total has file_scar";

  # Module-level SCAR (whole-codebase CRAP)
  ok exists $ts->{module_cc},   "filescar: Total has module_cc";
  ok exists $ts->{module_cov},  "filescar: Total has module_cov";
  ok exists $ts->{module_crap}, "filescar: Total has module_crap";
  ok exists $ts->{module_scar}, "filescar: Total has module_scar";
  ok $ts->{module_cc} > 0,      "filescar: module_cc > 0";
  my $mcc            = $ts->{module_cc};
  my $mcv            = $ts->{module_cov};
  my $expected_mcrap = $mcc**2 * (1 - $mcv / 100)**3 + $mcc;
  is $ts->{module_crap}, $expected_mcrap,
    "filescar: module_crap matches CRAP formula";
  my $expected_mscar
    = $ts->{module_crap} > 1 ? log($ts->{module_crap}) * 10 : 0;
  ok abs($ts->{module_scar} - $expected_mscar) < 0.01,
    "filescar: module_scar = log(module_crap) * 10";
}

sub test_dir_level_scar () {
  my ($db_path, $script) = run_cover("cc_dirscar", $Crap_script);

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
  my ($file) = grep /cc_dirscar\.pl$/, keys $db->{summary}->%*;
  ok defined $file, "dirscar: file found in summary";
  (my $dir = $file) =~ s|/[^/]+$||;
  my $ds = $db->dir_summary($dir);
  ok defined $ds, "dirscar: dir summary exists";

  # Per-criterion aggregation
  for my $c (qw( statement branch condition total )) {
    ok exists $ds->{$c},           "dirscar: has $c";
    ok defined $ds->{$c}{covered}, "dirscar: $c has covered";
    ok defined $ds->{$c}{total},   "dirscar: $c has total";
  }

  # SCAR entry
  my $scar = $ds->{scar};
  ok defined $scar,             "dirscar: has scar entry";
  ok exists $scar->{file_cc},   "dirscar: has file_cc";
  ok exists $scar->{file_cov},  "dirscar: has file_cov";
  ok exists $scar->{file_crap}, "dirscar: has file_crap";
  ok exists $scar->{file_scar}, "dirscar: has file_scar";

  # dir_cc should equal the single file's file_cc (one file in the directory)
  my $file_scar = $db->{summary}{$file}{scar};
  is $scar->{file_cc}, $file_scar->{file_cc},
    "dirscar: dir cc matches single file cc";

  # CRAP formula
  my $cc            = $scar->{file_cc};
  my $cov           = $scar->{file_cov};
  my $expected_crap = $cc**2 * (1 - $cov / 100)**3 + $cc;
  is $scar->{file_crap}, $expected_crap,
    "dirscar: dir crap matches CRAP formula";
}

# Helper: run the text report against a fresh db built from Crap_script and
# return the captured stdout, with full show options enabled.
sub _text_report_for ($label, $script = $Crap_script, @coverage) {
  my ($db_path, $script_path) = run_cover($label, $script);
  my $st = Devel::Cover::DB::Structure->new(base => $db_path);
  $st->read_all;
  my $db = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  $db->set_structure($st);
  @coverage = qw( statement branch condition subroutine ) unless @coverage;
  $db->calculate_summary(map { $_ => 1 } @coverage);

  my @files   = $db->cover->items;
  my $options = {
    show        => { map { $_ => 1 } @coverage },
    file        => \@files,
    annotations => [],
  };

  my $output;
  open my $fh, ">", \$output or die "Cannot open scalar ref: $!";
  local *STDOUT = $fh;
  Devel::Cover::Report::Text->report($db, $options);
  close $fh or die "Cannot close scalar ref: $!";
  $output
}

# Per-file SCAR banner tests.
# Verifies the text report emits a per-file banner showing
# CC / Coverage / CRAP / SCAR, plus a worst-subs digest.
sub test_text_file_banner () {
  my $output = _text_report_for("tx_banner");

  like $output, qr/^File Summary\b/m, "banner: File Summary heading present";
  like $output, qr/\bCC\b.*\bCov\b.*\bCRAP\b.*\bSCAR\b/,
    "banner: metrics table header";
  like $output, qr/^\s*\d+\s+\d+\.\d+\s+\d+\.\d+\s+\d+\.\d+\s*$/m,
    "banner: metrics table data row";

  like $output, qr/^Worst Subroutines\b/m,
    "banner: Worst Subroutines heading present";
  like $output, qr/\bSubroutine\b.*\bCC\b.*\bSCAR\b.*\bLocation\b/,
    "banner: worst-subs table header";
  like $output, qr/\bpartial_branch\b.*\d+\s+\d+\.\d+\s+\S*tx_banner\.pl:\d+/,
    "banner: partial_branch appears in worst-subs with CC/SCAR/location";
}

# Run a two-file coverage session by having the main script require a sibling
# .pm; return the db path and both script paths.
sub run_cover_two_files ($label, $split_dirs = 0) {
  my $base = File::Spec->catdir($Tmpdir, $label);
  mkdir $base;
  my $helper_dir = $split_dirs ? File::Spec->catdir($base, "sub") : $base;
  mkdir $helper_dir if $split_dirs;
  my $db     = File::Spec->catdir($base, "db");
  my $helper = File::Spec->catfile($helper_dir, "Helper.pm");
  my $main   = File::Spec->catfile($base,       "main.pl");

  open my $hfh, ">", $helper or die $!;
  print $hfh <<'PERL';
package Helper;
use strict;
use warnings;

sub risky {
  my ($x) = @_;
  if ($x) { return 1 }
  return 0;
}

sub safe { 42 }

1;
PERL
  close $hfh or die "Can't close $helper: $!";

  open my $mfh, ">", $main or die $!;
  print $mfh <<"PERL";
use strict;
use warnings;
use lib '$helper_dir';
use Helper;

Helper::safe();
PERL
  close $mfh or die "Can't close $main: $!";

  my @inc = map { "-I$_" } "$Root/blib/arch", "$Root/blib/lib", "$Root/lib";
  system($^X, @inc, "-MDevel::Cover=-db,$db,-silent,1", $main) == 0
    or die "Failed two-file cover run: $?";

  ($db, $main, $helper)
}

sub _multi_file_report ($label, $split_dirs = 0) {
  my ($db_path, $main, $helper) = run_cover_two_files($label, $split_dirs);
  my $st = Devel::Cover::DB::Structure->new(base => $db_path);
  $st->read_all;
  my $db = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  $db->set_structure($st);
  my @coverage = qw( statement branch condition subroutine );
  $db->calculate_summary(map { $_ => 1 } @coverage);

  my @files   = $db->cover->items;
  my $options = {
    show        => { map { $_ => 1 } @coverage },
    file        => \@files,
    annotations => [],
  };

  my $output;
  open my $fh, ">", \$output or die $!;
  local *STDOUT = $fh;
  Devel::Cover::Report::Text->report($db, $options);
  close $fh or die $!;
  $output
}

# Module-level SCAR block tests.
# Verifies the text report emits a Module Summary block at the top when more
# than one file is reported.
sub test_text_module_block () {
  my $output = _multi_file_report("tx_module");

  like $output, qr/^Module Summary\b/m,
    "module: Module Summary heading present";
  like $output, qr/\bFiles\b.*\bCC\b.*\bCov\b.*\bCRAP\b.*\bSCAR\b/,
    "module: metrics table header";
  like $output, qr/^\s*\d+\s+\d+\s+\d+\.\d+\s+\d+\.\d+\s+\d+\.\d+\s*$/m,
    "module: metrics table data row";

  # The Module Summary block should appear before the first File Summary.
  my $mod_pos  = index $output, "Module Summary";
  my $file_pos = index $output, "File Summary";
  ok $mod_pos >= 0 && $file_pos >= 0 && $mod_pos < $file_pos,
    "module: appears before per-file banners";
}

# Directory SCAR block tests.
# Verifies the text report emits a Directory Summary table at the end
# when more than one directory spans the reported files.
sub test_text_dir_block () {
  my $output = _multi_file_report("tx_dir", 1);

  like $output, qr/^Directory Summary\b/m,
    "dir: Directory Summary heading present";
  like $output, qr/\bDirectory\b.*\bCC\b.*\bCov\b.*\bCRAP\b.*\bSCAR\b/,
    "dir: table header present";

  # Directory block should appear after the last File Summary.
  my $dir_pos   = index $output, "Directory Summary";
  my $last_fsum = rindex $output, "File Summary";
  ok $dir_pos >= 0 && $last_fsum >= 0 && $dir_pos > $last_fsum,
    "dir: appears after per-file banners";
}

# When a report spans a single directory, no Directory Summary block.
sub test_text_dir_block_suppressed () {
  my $output = _multi_file_report("tx_dir_single", 0);
  unlike $output, qr/^Directory Summary\b/m,
    "dir: suppressed when only one directory in report";
}

# print_summary SCAR column tests.
# Verifies that DB::print_summary emits a scar column after the criteria
# columns, with per-file file_scar and Total module_scar.
sub test_print_summary_scar () {
  my ($db_path, $script) = run_cover("ps_scar", $Crap_script);

  my $st = Devel::Cover::DB::Structure->new(base => $db_path);
  $st->read_all;

  my $db = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  $db->set_structure($st);

  my $output;
  {
    open my $fh, ">", \$output or die "Cannot open scalar ref: $!";
    local *STDOUT = $fh;
    local $ENV{DEVEL_COVER_TEST_SUITE} = 1;
    $db->print_summary(
      undef,
      [qw( statement branch condition subroutine )],
      { force => 1 },
    );
    close $fh or die "Cannot close scalar ref: $!";
  }

  like $output, qr/\bscar\b/, "summary: header contains scar column";

  my ($file_row) = $output =~ /^(\S*ps_scar\.pl\s.+)$/m;
  ok defined $file_row, "summary: file row found";
  my @file_cols = split " ", $file_row // "";
  is @file_cols, 7,
    "summary: file row has name + 5 criteria + scar (7 cols)";
  like $file_cols[-1], qr/^\d+\.\d$/,
    "summary: file row scar column is numeric";

  my ($total_row) = $output =~ /^(Total\s.+)$/m;
  ok defined $total_row, "summary: Total row found";
  my @total_cols = split " ", $total_row // "";
  is @total_cols, 7,
    "summary: Total row has label + 5 criteria + scar (7 cols)";
  like $total_cols[-1], qr/^\d+\.\d$/,
    "summary: Total row scar column is numeric";
}

sub main () {
  test_cc_counting;
  test_summary_aggregation;
  test_end_lines;
  test_signature_cc;
  test_scar_scoring;
  test_text_report_scar;
  test_file_level_scar;
  test_dir_level_scar;
  test_print_summary_scar;
  test_text_file_banner;
  test_text_module_block;
  test_text_dir_block;
  test_text_dir_block_suppressed;
}

main;
done_testing;

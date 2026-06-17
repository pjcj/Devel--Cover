#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# Per-execution decision input vectors are recorded at runtime via XS and
# appear in the cover_db at $Run{decision_inputs}{$file}[$n]{$vector_key} =
# count.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Cwd        qw( abs_path );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is is_deeply ok subtest )];

use Devel::Cover::DB   ();
use Devel::Cover::Mcdc ();

my $Tmpdir = tempdir(CLEANUP => 1);

# A mock condition entry matching the structure Devel::Cover produces:
#   [0] hit counts per outcome, [1] {type, left, op, right}, [2] uncoverable
#   markers per outcome.
sub mock_condition ($class, $hits, $info, $unc = undef) {
  bless [$hits, $info, $unc], "Devel::Cover::$class"
}

sub write_script ($name, $content) {
  my $path = File::Spec->catfile($Tmpdir, $name);
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
  $path
}

sub run_under_cover ($script, $label, @criteria) {
  my $cover_db   = File::Spec->catdir($Tmpdir, "cover_db_$label");
  my $abs_tmpdir = abs_path($Tmpdir);
  my $coverage   = @criteria ? "-coverage," . join(",", @criteria) . "," : "";
  my @cmd        = (
    $^X, "-Iblib/lib", "-Iblib/arch",
    "-MDevel::Cover=-db,$cover_db,-silent,1,${coverage}+select,$abs_tmpdir",
    $script,
  );
  system(@cmd) == 0 or die "Failed to run script under Devel::Cover: @cmd";

  my $db = Devel::Cover::DB->new(db => $cover_db);
  $db->merge_runs;
  my $real_path = abs_path($script);
  ($db, $real_path)
}

sub decision_inputs_for ($db, $file) {
  for my $run (values $db->{runs}->%*) {
    return $run->{decision_inputs}{$file} if $run->{decision_inputs}{$file};
  }
  return;
}

sub test_simple_and () {
  my $script = write_script("simple_and.pl", <<'PERL');
my @r;
sub two { my ($p, $q) = @_; push @r, $p && $q }
two(1, 1);
two(1, 0);
two(0, 1);
two(0, 0);
PERL

  my ($db, $path) = run_under_cover($script, "simple_and");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for simple_and";
  is @$di, 1, "one decision recorded";

  is_deeply $di->[0], { "1|1" => 1, "1|0" => 1, "0|X" => 2 },
    "vectors and counts: (1,1), (1,0), and two short-circuits to (0,X)";
}

sub test_worked_example () {
  my $script = write_script("worked.pl", <<'PERL');
my @r;
sub may_edit {
  my ($is_owner, $unlocked, $is_admin) = @_;
  push @r, ($is_owner && $unlocked) || $is_admin;
}
may_edit(1, 1, 1);
may_edit(1, 0, 1);
may_edit(0, 0, 1);
may_edit(0, 0, 0);
PERL

  my ($db, $path) = run_under_cover($script, "worked");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for worked example";

  # Find the entry recording the outer || root (3 columns; 4 distinct
  # observed vectors).  Inner && entries have no decision_inputs.
  my @recorded = grep defined, @$di;
  is @recorded, 1, "exactly one root recorded (outer ||)";

  is_deeply $recorded[0],
    { "1|1|X" => 1, "1|0|1" => 1, "0|X|1" => 1, "0|X|0" => 1 },
    "four distinct observed vectors, no phantom (1,0,0)";
}

sub test_repeated_observation () {
  my $script = write_script("repeated.pl", <<'PERL');
my @r;
sub two { my ($p, $q) = @_; push @r, $p && $q }
two(1, 1) for 1 .. 3;
two(0, 0) for 1 .. 5;
PERL

  my ($db, $path) = run_under_cover($script, "repeated");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for repeated";

  is_deeply $di->[0], { "1|1" => 3, "0|X" => 5 },
    "counts accumulate across executions";
}

sub test_no_inputs_without_mcdc () {
  my $script = write_script("no_mcdc.pl", <<'PERL');
my @r;
sub two { my ($p, $q) = @_; push @r, $p && $q }
two(1, 1);
two(1, 0);
two(0, 1);
two(0, 0);
PERL

  my ($db, $path) = run_under_cover(
    $script, "no_mcdc", qw( statement branch condition subroutine )
  );
  my $di = decision_inputs_for($db, $path);
  ok !$di, "decision_inputs absent when mcdc not selected";
}

# A compound decision in void/boolean context records no observed vectors;
# synthesis must not then fabricate a false 100% MC/DC.
sub test_void_compound_no_false_coverage () {
  my $script = write_script("void_compound.pl", <<'PERL');
sub decision {
  my ($a, $b, $c, $d) = @_;
  if (($a && $b) || ($c && $d)) { return 1 }
  return 0;
}
decision(1, 1, 0, 0);
decision(0, 0, 0, 0);
decision(0, 0, 1, 1);
decision(1, 0, 1, 0);
PERL

  my ($db, $path) = run_under_cover($script, "void_compound");
  my $mcdc = $db->cover->file($path)->{mcdc};
  ok $mcdc, "mcdc derived for void compound decision";

  my ($decision) = grep $_->total >= 3, map @$_, values %$mcdc;
  ok $decision, "found the compound decision";
  is $decision->total,   4, "four atomics";
  is $decision->covered, 0, "synthesised compound claims no MC/DC coverage";
  ok $decision->error, "MC/DC error flagged, not a false 100%";
}

# The analyser derives its uncoverable set from the synthesised rows.  For an
# unproven table those rows are the evidence we distrust, so a column the
# analyser excused must not be silently excused in the derived MC/DC result;
# only explicit "# uncoverable mcdc" markers may excuse one there.
sub test_unproven_ignores_derived_uncoverable () {
  my $db = bless {}, "Devel::Cover::DB";

  # Worked example $a || ($b && $c): a compound decision, so unproven without
  # observed vectors.  The inner "# uncoverable condition" marker lets the
  # analyser excuse $c through the synthesised rows.
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 0, 1],
      { type => "and_3", left => '$b', op => "&&", right => '$c' },
      [0, 1, 0],
    ),
    mock_condition(
      "Condition_or_3",
      [1, 1, 1],
      { type => "or_3", left => '$a', op => "||", right => '$b && $c' },
    ),
  );

  my $cover
    = { f1 => { condition => { 10 => \@conditions }, meta => { digest => "d" } }
    };
  $db->_derive_mcdc($cover);

  my $decision = bless $cover->{f1}{mcdc}{10}[0], "Devel::Cover::Mcdc";
  is $decision->covered, 0, "unproven table claims no MC/DC coverage";
  ok !$decision->uncoverable, "no atomic excused from an unproven table";
  is_deeply $decision->missing, ['$a', '$b', '$c'],
    "every atomic of an unproven table is reported missing";
}

sub test_add_condition_cross_run_merge () {
  my $db = bless {}, "Devel::Cover::DB";
  my $cc = {};
  my $sc = [[42, { type => "or_3" }]];
  my $uc = { 42 => [[]] };

  $db->add_condition($cc, $sc, [[1, 0, 2]], $uc, [{ "1|1" => 1, "1|0" => 2 }]);
  $db->add_condition($cc, $sc, [[3, 4, 0]], $uc, [{ "1|1" => 5, "0|X" => 7 }]);

  is_deeply $cc->{42}[0][0], [4, 4, 2],
    "hit counts sum across runs (slots 0-2)";

  is_deeply $cc->{42}[0][3], { "1|1" => 6, "1|0" => 2, "0|X" => 7 },
    "observed-vector counts merged: shared key sums, new keys appended";
}

sub test_add_condition_xor_four_slot_merge () {
  my $db = bless {}, "Devel::Cover::DB";
  my $cc = {};
  my $sc = [[7, { type => "xor_4" }]];
  my $uc = { 7 => [[]] };

  $db->add_condition($cc, $sc, [[1, 2, 3, 4]], $uc);
  $db->add_condition($cc, $sc, [[5, 6, 7, 8]], $uc);

  is_deeply $cc->{7}[0][0], [6, 8, 10, 12],
    "xor four-slot hit counts (slots 0-3) sum across runs";
}

sub main () {
  subtest "simple two-leaf and"    => \&test_simple_and;
  subtest "worked example"         => \&test_worked_example;
  subtest "repeated observation"   => \&test_repeated_observation;
  subtest "no inputs without mcdc" => \&test_no_inputs_without_mcdc;
  subtest "void compound no false coverage" =>
    \&test_void_compound_no_false_coverage;
  subtest "unproven ignores derived uncoverable" =>
    \&test_unproven_ignores_derived_uncoverable;
  subtest "cross-run merge"     => \&test_add_condition_cross_run_merge;
  subtest "xor four-slot merge" => \&test_add_condition_xor_four_slot_merge;

  done_testing;
}

main;

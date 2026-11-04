#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# A right operand that dies leaves its logop pending on the op after the right
# operand.  When something catches the die, that evaluation must record no value
# for the right operand, and a later run that reaches the same op must count
# only itself.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is_deeply subtest )];

use Devel::Cover::Test::Internal qw( write_script run_under_cover );

my $Subs = <<'PERL';
my $n = 0;
sub maybe { $n++ ? 1 : die "no\n" }
sub dies { die "no\n" }
PERL

# The script body starts on line 4, after the three lines of $Subs.
sub run_script ($label, $body, $criteria = ["condition"]) {
  my $script = write_script("$label.pl", $Subs . $body);
  my ($db, $path) = run_under_cover($script, $label, criteria => $criteria);
  ($db->cover, $path)
}

# Return the hit counts of a line for a criterion, outermost record first.
sub values_for ($cover, $file, $line, $criterion = "condition") {
  my $crit = $cover->file($file)->criterion($criterion) or return [];
  my @recs
    = sort { length $b->{text} <=> length $a->{text} }
    map +{ text => $_->text, values => $_->values },
    ($crit->location($line) // [])->@*;
  [map $_->{values}, @recs]
}

# The first call dies in the right operand and the second completes.
sub test_rerun_after_die () {
  my ($cover, $path) = run_script("rerun", <<'PERL');
sub f { my $r = $_[0] || maybe(); $r }
eval { f(0) } for 1 .. 2;
PERL

  is_deeply values_for($cover, $path, 4), [[0, 1, 0]],
    "only the completed run is counted";
}

# The second run reaches the hooked op by the other branch of the ternary.
sub test_other_path () {
  my ($cover, $path) = run_script("other_path", <<'PERL');
sub f { my $r = $_[0] ? ($_[1] || dies()) : $_[1]; $r }
eval { f(1, 0) };
eval { f(0, 7) };
PERL

  is_deeply values_for($cover, $path, 4), [[0, 0, 0]],
    "the run that died is not counted";
}

# The second run short circuits at the inner || op and skips the outer one.
sub test_short_circuit_resolves () {
  my ($cover, $path) = run_script("short_circuit", <<'PERL');
sub f { my $r = $_[0] || dies() || 5; $r }
eval { f($_) } for 0, 1;
PERL

  is_deeply values_for($cover, $path, 4), [[1, 0], [1, 0, 0]],
    "the short circuit does not count the run that died";
}

# Return the condition hit counts of a line, keyed by the text of each record.
sub values_by_text ($cover, $file, $line) {
  my $cond = $cover->file($file)->criterion("condition") or return {};
  +{ map { $_->text => $_->values } ($cond->location($line) // [])->@* }
}

# A completed run one frame shallower resolves the list both || ops share.
sub test_deeper_run_resolves () {
  my ($cover, $path) = run_script("deeper", <<'PERL');
sub f {
  my $r = $_[0] ? ($_[1] || maybe())
                : ($_[2] || maybe()); $r }
eval { f(1, 0, 0) };
f(0, 0, 0);
PERL

  my $values = values_by_text($cover, $path, 5);
  is_deeply $values->{'$_[1] or maybe()'}, [0, 0, 0],
    "the run that died is not counted";
  is_deeply $values->{'$_[2] or maybe()'}, [0, 1, 0],
    "the completed run is counted once";
}

sub test_and_and_dor () {
  my ($cover, $path) = run_script("and", <<'PERL');
sub f { my $r = $_[0] && maybe(); $r }
eval { f(1) } for 1 .. 2;
PERL

  is_deeply values_for($cover, $path, 4), [[0, 0, 1]],
    "and counts only the completed run";

  ($cover, $path) = run_script("dor", <<'PERL');
sub f { my $r = $_[0] // maybe(); $r }
eval { f(undef) } for 1 .. 2;
PERL

  is_deeply values_for($cover, $path, 4), [[0, 1, 0]],
    "dor counts only the completed run";
}

# The only run dies in the right operand and nothing runs the op again.
sub test_die_once () {
  my ($cover, $path) = run_script("die_once", <<'PERL');
sub f { my $r = $_[0] || dies(); $r }
eval { f(0) };
PERL

  is_deeply values_for($cover, $path, 4), [[0, 0, 0]],
    "the run that died is not counted";
}

# The right operand of an if condition dies.
sub test_die_in_if () {
  my ($cover, $path) = run_script("die_in_if", <<'PERL');
sub f { if ($_[0] || dies()) { return 1 } 0 }
eval { f(0) };
PERL

  is_deeply values_for($cover, $path, 4), [[0, 0, 0]],
    "the run that died is not counted";
}

# Devel::Cover counts an exit in the right operand when the logop runs.
sub test_exit_right () {
  my ($cover, $path) = run_script("exit_right", <<'PERL');
sub f { my $r = $_[0] || exit 0; $r }
f(0);
PERL

  is_deeply values_for($cover, $path, 4), [[0, 1]], "exit counts one !l";
}

# A false left operand gives !l whatever value the right operand has.
sub test_two_outcome_die () {
  my ($cover, $path) = run_script("two_outcome_die", <<'PERL');
sub t { my $r = $_[0] || [ dies() ]; $r }
eval { t(0) };
t(1);
PERL

  is_deeply values_for($cover, $path, 4), [[1, 1]],
    "the run that died counts as !l";
}

sub test_two_outcome_dor () {
  my ($cover, $path) = run_script("two_outcome_dor", <<'PERL');
sub t { my $r = $_[0] // ($_[1] ? "a" : die "no\n"); $r }
eval { t(undef, 0) };
t(1, 0);
PERL

  is_deeply values_for($cover, $path, 4), [[1, 1]],
    "the run that died counts as !l";
}

# An exit inside a called sub leaves the entry pending at the end of the run.
sub test_two_outcome_exit () {
  my ($cover, $path) = run_script("two_outcome_exit", <<'PERL');
sub t { my $r = $_[0] || [ quit() ]; $r }
sub quit { exit 0 }
t(1);
t(0);
PERL

  is_deeply values_for($cover, $path, 4), [[1, 1]],
    "the run that exited counts as !l";
}

my $Branch_criteria = ["statement", "branch", "condition"];

sub test_branch_die () {
  my ($cover, $path) = run_script("branch_die", <<'PERL', $Branch_criteria);
sub g { $_[0] or dies() }
eval { my $v = g(0) };
my $w = g(1);
PERL

  is_deeply values_for($cover, $path, 4, "branch"), [[1, 1]],
    "the run that died counts on the branch it took";
}

sub test_branch_exit () {
  my ($cover, $path) = run_script("branch_exit", <<'PERL', $Branch_criteria);
sub g { $_[0] or quit() }
sub quit { exit 0 }
my $w = g(1);
my $v = g(0);
PERL

  is_deeply values_for($cover, $path, 4, "branch"), [[1, 1]],
    "the run that exited counts on the branch it took";
}

sub main () {
  subtest "rerun after die"        => \&test_rerun_after_die;
  subtest "other path"             => \&test_other_path;
  subtest "short circuit resolves" => \&test_short_circuit_resolves;
  subtest "deeper run resolves"    => \&test_deeper_run_resolves;
  subtest "and and dor"            => \&test_and_and_dor;
  subtest "die once"               => \&test_die_once;
  subtest "die in if"              => \&test_die_in_if;
  subtest "exit right"             => \&test_exit_right;
  subtest "two outcome die"        => \&test_two_outcome_die;
  subtest "two outcome dor"        => \&test_two_outcome_dor;
  subtest "two outcome exit"       => \&test_two_outcome_exit;
  subtest "branch die"             => \&test_branch_die;
  subtest "branch exit"            => \&test_branch_exit;

  done_testing;
}

main;

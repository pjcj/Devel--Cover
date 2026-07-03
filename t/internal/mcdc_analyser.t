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

use Test::More import => [qw( done_testing is is_deeply ok )];

use Devel::Cover::Condition_table ();
use Devel::Cover::Mcdc::Analyser  ();

# Build a mock condition object: blessed arrayref matching the structure that
# Devel::Cover produces.
#   [0] = arrayref of hit counts per path
#   [1] = hashref with {type, left, op, right}
sub mock_condition ($class, $hits, $info) {
  bless [$hits, $info], "Devel::Cover::$class"
}

# $a && $b: hits index 0 = !l (A=F, B=X), 1 = l&&!r (A=T, B=F), 2 = l&&r.
sub build_and_table ($hits) {
  my @conditions = (mock_condition(
    "Condition_and_3", $hits,
    { type => "and_3", left => '$a', op => "&&", right => '$b' },
  ));
  my ($table) = Devel::Cover::Condition_table->for_line(\@conditions);
  $table
}

# $a || $b: hits index 0 = l (A=T, B=X), 1 = !l&&r (A=F, B=T), 2 = !l&&!r.
sub build_or_table ($hits) {
  my @conditions = (mock_condition(
    "Condition_or_3", $hits,
    { type => "or_3", left => '$a', op => "||", right => '$b' },
  ));
  my ($table) = Devel::Cover::Condition_table->for_line(\@conditions);
  $table
}

sub test_api_keys () {
  my $table  = build_and_table([1, 1, 1]);
  my $result = Devel::Cover::Mcdc::Analyser->analyse($table);

  is ref $result, "HASH", "analyse returns a hashref";
  ok exists $result->{total},     "result has total key";
  ok exists $result->{satisfied}, "result has satisfied key";
  ok exists $result->{pairs},     "result has pairs key";
  ok exists $result->{missing},   "result has missing key";
}

sub test_and_satisfying () {
  my $r = Devel::Cover::Mcdc::Analyser->analyse(build_and_table([1, 1, 1]));
  is $r->{total},     2, "and full: 2 atomics";
  is $r->{satisfied}, 2, "and full: both atomics satisfied";
}

sub test_and_missing () {
  my $r = Devel::Cover::Mcdc::Analyser->analyse(build_and_table([1, 0, 0]));
  is $r->{total},     2, "and !l only: 2 atomics";
  is $r->{satisfied}, 0, "and !l only: neither atomic satisfied";
}

sub test_or_satisfying () {
  my $r = Devel::Cover::Mcdc::Analyser->analyse(build_or_table([1, 1, 1]));
  is $r->{total},     2, "or full: 2 atomics";
  is $r->{satisfied}, 2, "or full: both atomics satisfied";
}

sub test_or_missing () {
  my $r = Devel::Cover::Mcdc::Analyser->analyse(build_or_table([0, 0, 1]));
  is $r->{total},     2, "or !l&&!r only: 2 atomics";
  is $r->{satisfied}, 0, "or !l&&!r only: neither atomic satisfied";
}

# Rows [0, X] and [1, 1]: A varies, B is X vs 1.  Under short-circuit-aware
# unique-cause, X agrees with the concrete 1, so A is satisfied.  B is only
# seen as X and 1, so it is not.
sub test_and_x_pairs_with_concrete () {
  my $r = Devel::Cover::Mcdc::Analyser->analyse(build_and_table([1, 0, 1]));
  is $r->{total},     2, "and short+full: 2 atomics";
  is $r->{satisfied}, 1, "and short+full: A satisfied via X agreeing with 1";
}

# Rows [1, X] and [0, 0]: A varies, B is X vs 0.  X agrees with 0, so A is
# satisfied.  B is only seen as X and 0, so it is not.
sub test_or_x_pairs_with_concrete () {
  my $r = Devel::Cover::Mcdc::Analyser->analyse(build_or_table([1, 0, 1]));
  is $r->{total},     2, "or short+!l&&!r: 2 atomics";
  is $r->{satisfied}, 1, "or short+!l&&!r: A satisfied via X agreeing with 0";
}

# Rows [1, 0] and [1, 1]: no X anywhere; B is satisfied through a concrete-only
# pair, A is not (only A=1 observed).
sub test_and_concrete_only_pair () {
  my $r = Devel::Cover::Mcdc::Analyser->analyse(build_and_table([0, 1, 1]));
  is $r->{total},     2, "and !short+full: 2 atomics";
  is $r->{satisfied}, 1, "and !short+full: B satisfied via concrete pair";
}

# Rows [0, 0] and [0, 1]: no X anywhere; B is satisfied through a concrete-only
# pair, A is not (only A=0 observed).
sub test_or_concrete_only_pair () {
  my $r = Devel::Cover::Mcdc::Analyser->analyse(build_or_table([0, 1, 1]));
  is $r->{total},     2, "or !short+!l&&!r: 2 atomics";
  is $r->{satisfied}, 1, "or !short+!l&&!r: B satisfied via concrete pair";
}

# Build a Condition_table::Table directly from synthetic rows.  Used to test
# coupled-condition behaviour: a coupled decision such as
# ($a && $b) || ($a && $c) builds one table with a repeated label.
sub build_synthetic_table ($expr, $labels, $rows) {
  my @row_objects = map {
    Devel::Cover::Condition_table::Row->new(
      inputs      => $_->{inputs},
      result      => $_->{result},
      covered     => $_->{covered}     // 1,
      uncoverable => $_->{uncoverable} // 0,
    )
  } @$rows;
  Devel::Cover::Condition_table::Table->new(
    expr   => $expr,
    labels => $labels,
    rows   => \@row_objects,
  )
}

# Coupled column 0 and column 2 (both labelled $a).  Unique-cause cannot pair
# the two rows for column 0 because column 2 disagrees, but masking allows the
# other occurrence of $a to vary.
sub test_masking_fires_when_coupled () {
  my $table = build_synthetic_table(
    '($a && $b) || ($a && $c)',
    ['$a', '$b', '$a'],
    [
      { inputs => [1, 1, 1], result => 1 },
      { inputs => [0, 1, 0], result => 0 },
    ],
  );
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is $r->{total},     3, "coupled: 3 columns";
  is $r->{satisfied}, 2, 'coupled: both $a columns satisfied via masking';
}

# Same row data, distinct labels.  Without coupling, masking must not fire and
# the column-0 / column-2 pair stays unsatisfied.
sub test_masking_does_not_fire_when_uncoupled () {
  my $table = build_synthetic_table(
    '$a && $b && $c',
    ['$a', '$b', '$c'],
    [
      { inputs => [1, 1, 1], result => 1 },
      { inputs => [0, 1, 0], result => 0 },
    ],
  );
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is $r->{total},     3, "uncoupled: 3 columns";
  is $r->{satisfied}, 0, "uncoupled: masking never fires";
}

# Condition_table::for_line places X-rows ahead of concrete rows, so
# `_concrete_differs` and `_sca_agrees` only see X as their first argument in
# normal runs.  This synthetic ordering puts the X-row second and exercises the
# X short-circuit on the second argument in both helpers.
sub test_x_as_second_argument () {
  my $table = build_synthetic_table(
    '$a && $b',
    ['$a',                              '$b'],
    [{ inputs => [1, 1], result => 1 }, { inputs => [0, "X"], result => 0 }],
  );
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is $r->{total},     2, "x-second: 2 atomics";
  is $r->{satisfied}, 1, 'x-second: $a satisfied via X agreeing with 1';
}

# missing is empty when every atomic has been demonstrated.
sub test_missing_empty_when_all_satisfied () {
  my $r = Devel::Cover::Mcdc::Analyser->analyse(build_and_table([1, 1, 1]));
  is_deeply $r->{missing}, [], "all satisfied: missing list is empty";
}

# missing names exactly the columns that lack pairs, in column order.
sub test_missing_lists_unsatisfied_columns () {
  my $r = Devel::Cover::Mcdc::Analyser->analyse(build_and_table([0, 1, 1]));
  is_deeply $r->{missing}, ['$a'],
    "and !short: missing lists the unsatisfied column";
}

# Both columns missing when no pair can be found at all.
sub test_missing_lists_all_columns () {
  my $r = Devel::Cover::Mcdc::Analyser->analyse(build_and_table([1, 0, 0]));
  is_deeply $r->{missing}, ['$a', '$b'],
    "and !l only: missing lists both columns";
}

# Worked-example regression: nested `($is_owner && $unlocked) || $is_admin`
# exercised with the four tests listed in `docs/technical/mcdc.md`.  Hits both
# sub-decisions in full (inner [1,1,1], outer [1,1,1]).  The four observed
# combined inputs (T,T,X), (T,F,T), (F,X,T), (F,X,F) demonstrate SCA
# independence pairs for `$is_owner` and `$is_admin`, leaving `$unlocked` as the
# only atomic without a pair.  SCA MC/DC: 2/3 satisfied, missing `$unlocked`.
# Without observed-vectors, `Condition_table::for_line` synthesises composite
# rows by cross-product, producing a phantom (T,F,F) covered=1 row that lets the
# analyser build a spurious pair for `$unlocked`. Passing observed-vectors in
# is what blocks the phantom: rows are marked covered iff their input vector
# was actually executed.
sub test_no_phantom_rows_in_worked_example () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 1, 1], {
        type  => "and_3",
        left  => '$is_owner',
        op    => "&&",
        right => '$unlocked',
      },
    ),
    mock_condition(
      "Condition_or_3",
      [1, 1, 1], {
        type  => "or_3",
        left  => '$is_owner && $unlocked',
        op    => "||",
        right => '$is_admin',
      },
    ),
  );
  # Outer || is the root (index 1); decision_inputs is populated only at root
  # entries.
  my @observed = (
    undef, {
      "1|1|X" => 1,  # (T,T,X) - $is_admin not evaluated
      "1|0|1" => 1,  # (T,F,T)
      "0|X|1" => 1,  # (F,X,T) - $unlocked not evaluated
      "0|X|0" => 1,  # (F,X,F)
    },
  );
  my ($table)
    = Devel::Cover::Condition_table->for_line(\@conditions, \@observed);
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is $r->{total}, 3, "worked example: 3 atomics";
  is $r->{satisfied}, 2,
    'worked example: $is_owner and $is_admin satisfied via SCA pairs';
  is_deeply $r->{missing}, ['$unlocked'],
    'worked example: $unlocked is the only atomic missing a pair';
}

# Coupled labels appear in their column order, including duplicates, so the
# total / satisfied / missing accounts stay consistent at the column level.
# Both $a columns are held at 1, so neither has a variation pair.
sub test_missing_preserves_coupled_columns () {
  my $table = build_synthetic_table(
    '($a && $b) || ($a && $c)',
    ['$a', '$b', '$a'],
    [
      { inputs => [1, 1, 1], result => 1 },
      { inputs => [1, 0, 1], result => 0 },
    ],
  );
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is $r->{total},     3, "coupled missing: 3 columns";
  is $r->{satisfied}, 1, 'coupled missing: only $b satisfied';
  is_deeply $r->{missing}, ['$a', '$a'],
    'coupled: both $a columns listed in column order';
}

# Regression: a defined-or (or any logop) with a constant right operand
# collapses to a 2-outcome boolean table (or_2) whose rows carry a SINGLE input
# (the left operand): [0] and [1].  But the runtime records decision-input
# vectors for the UNCOLLAPSED expression, so on some perls (e.g. 5.28) the
# observed vectors are two-element - "1|X" (left short-circuits, right not
# evaluated) and "0|1" (left false, constant right) - matching neither
# one-element row.  for_line then marks every row uncovered and MC/DC reports
# 0% even though both outcomes were exercised (condition coverage sees both).
#
# Models `$x // {}` run with the left both defined (18x) and undef (2x).  With
# both outcomes exercised the single atomic must be satisfied; the dimension
# mismatch between observed vectors and collapsed rows must not lose coverage.
sub test_const_right_collapsed_observed_vectors () {
  my @conditions = (mock_condition(
    "Condition_or_2", [18, 2],
    { type => "or_2", left => '$x', op => "//", right => "{}" },
  ));
  # As recorded by the runtime for the uncollapsed `//`: two-element vectors.
  my @observed = ({ "1|X" => 18, "0|1" => 2 });
  my ($table)
    = Devel::Cover::Condition_table->for_line(\@conditions, \@observed);
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is $r->{total},     1, "const-right collapse: 1 atomic";
  is $r->{satisfied}, 1, "const-right collapse: left atomic satisfied";
  is_deeply $r->{missing}, [],
    "const-right collapse: nothing missing when both outcomes exercised";
}

# The const-right collapse is operator-general: `||` (and `&&`, `or`, `and`)
# collapse the same way as `//`.  Models `$x || 0` with the left true (short-
# circuit, right not evaluated -> "1|X") and false (right `0` evaluated ->
# "0|0").  Same two-element-vs-one-element mismatch as the `//` case; the single
# atomic must still be satisfied.
sub test_const_right_or_operator () {
  my @conditions = (mock_condition(
    "Condition_or_2", [12, 4],
    { type => "or_2", left => '$x', op => "||", right => "0" },
  ));
  my @observed = ({ "1|X" => 12, "0|0" => 4 });
  my ($table)
    = Devel::Cover::Condition_table->for_line(\@conditions, \@observed);
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is $r->{total},     1, "const-right ||: 1 atomic";
  is $r->{satisfied}, 1, "const-right ||: left atomic satisfied";
  is_deeply $r->{missing}, [], "const-right ||: nothing missing";
}

# Const-right collapse with a COMPOUND left operand: `($a && $b) // {}`.  The
# outer `//` collapses to a boolean table, but its left is itself a decision, so
# the rows expand back to the two atomics $a and $b - they are two-element
# (`0|X`, `1|0`, `1|1`).  The runtime records three-element vectors for the
# uncollapsed expression ($a, $b, and the un-skipped constant right).  The
# reconciliation must drop only the trailing constant column, keeping BOTH left
# operands - a projection that merely took the first element would key these
# rows wrongly and lose $b.  Exercises $a && $b in full so both atomics earn a
# pair.
sub test_const_right_compound_left_observed_vectors () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 1, 1],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_or_2", [16, 4],
      { type => "or_2", left => '$a && $b', op => "//", right => "{}" },
    ),
  );
  # Three-element vectors, as a non-skipping perl records for
  # `($a && $b) // {}`:
  #   1|1|X  $a true, $b true  -> left defined, right not evaluated
  #   1|0|X  $a true, $b false -> left defined (false), right not evaluated
  #   0|X|X  $a false          -> left defined (false), right not evaluated
  my @observed = (undef, { "1|1|X" => 8, "1|0|X" => 5, "0|X|X" => 3 });
  my ($table)
    = Devel::Cover::Condition_table->for_line(\@conditions, \@observed);
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is $r->{total},     2, "compound left: 2 atomics";
  is $r->{satisfied}, 2, "compound left: both atomics satisfied";
  is_deeply $r->{missing}, [],
    "compound left: nothing missing, trailing const column dropped";
}

# A column whose only independence pair needs an uncoverable row is excused
# rather than reported as missing.  Here $b's pair needs the l&&!r row, which is
# uncoverable, so $b is excused while $a is satisfied by a covered pair.
sub test_uncoverable_row_excuses_column () {
  my $table = build_synthetic_table(
    '$a && $b',
    ['$a', '$b'],
    [
      { inputs => [0, "X"], result => 0, covered => 1 },
      { inputs => [1, 0],   result => 0, covered => 0, uncoverable => 1 },
      { inputs => [1, 1],   result => 1, covered => 1 },
    ],
  );
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is $r->{satisfied}, 1, "excused: a satisfied via covered pair";
  ok $r->{uncoverable}{1}, "excused: b column excused by uncoverable row";
  is_deeply $r->{missing}, [], "excused: b not listed as missing";
}

# When no pair exists even with uncoverable rows allowed, the column stays
# missing rather than being excused.
sub test_no_pair_even_with_uncoverable_stays_missing () {
  my $table = build_synthetic_table(
    '$a && $b',
    ['$a', '$b'],
    [{ inputs => [1, 1], result => 1, covered => 1 }],
  );
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is_deeply $r->{missing}, ['$a', '$b'], "missing when no pair is possible";
  is_deeply $r->{uncoverable}, {},
    "nothing excused without an uncoverable pair";
}

# Like mock_condition but carrying an uncoverable arrayref ([2]).
sub mock_condition_unc ($class, $hits, $info, $unc) {
  bless [$hits, $info, $unc], "Devel::Cover::$class"
}

# A compound decision `$a && $b && $c`, parsed `($a && $b) && $c`.  $inner_unc
# and $outer_unc are the per-outcome uncoverable arrayrefs ([2]) for the two
# conditions, or undef.  The inner condition is addressed so the outer can
# reference it as its left operand.  $observed, if given, sets which combined
# rows count as covered, as the runtime would record them.
sub build_and3_compound ($inner_unc, $outer_unc, $observed = undef) {
  my $inner = mock_condition_unc(
    "Condition_and_3",
    [1, 1, 1],
    { type => "and_3", left => '$a', op => "&&", right => '$b', addr => 1 },
    $inner_unc,
  );
  my $outer = mock_condition_unc(
    "Condition_and_3",
    [1, 1, 1], {
      type      => "and_3",
      left      => '$a && $b',
      left_addr => 1,
      op        => "&&",
      right     => '$c',
    },
    $outer_unc,
  );
  my ($table)
    = Devel::Cover::Condition_table->for_line([$inner, $outer], $observed);
  $table
}

# Map a built table's rows to "input-vector => uncoverable (0/1)".
sub uncoverable_by_inputs ($table) {
  my %u;
  $u{ join "|", $_->inputs->@* } = $_->uncoverable ? 1 : 0 for $table->rows;
  \%u
}

# A leaf operand's uncoverable outcome propagates through the outer operator's
# row expansion.  Marking the inner `$a && !$b` outcome (index 1) uncoverable
# makes the combined `1|0|X` row - the only one built from that inner row -
# uncoverable, and no other.
sub test_compound_inner_uncoverable_propagates () {
  my $u = uncoverable_by_inputs(build_and3_compound([0, 1, 0], undef));
  is $u->{"1|0|X"}, 1, "inner marker: combined 1|0|X uncoverable";
  is_deeply [grep $u->{$_}, sort keys %$u], ["1|0|X"],
    "inner marker: only that row is uncoverable";
}

# The outer operator's own uncoverable outcome propagates to the combined rows
# it produces.  Marking the outer `(...) && !$c` outcome (index 1) uncoverable
# makes the combined `1|1|0` row uncoverable, and no other.
sub test_compound_outer_uncoverable_propagates () {
  my $u = uncoverable_by_inputs(build_and3_compound(undef, [0, 1, 0]));
  is $u->{"1|1|0"}, 1, "outer marker: combined 1|1|0 uncoverable";
  is_deeply [grep $u->{$_}, sort keys %$u], ["1|1|0"],
    "outer marker: only that row is uncoverable";
}

# End to end through the analyser: a leaf marker on a compound decision excuses
# the dependent column.  $a && $b && $c is exercised so $a and $c earn covered
# pairs, but $b's only independence pair needs the inner-marked `1|0|X` row, so
# $b is excused rather than reported missing.
sub test_compound_uncoverable_excuses_column () {
  my @observed = (undef, { "0|X|X" => 1, "1|1|0" => 1, "1|1|1" => 1 });
  my $table    = build_and3_compound([0, 1, 0], undef, \@observed);
  my $r        = Devel::Cover::Mcdc::Analyser->analyse($table);
  is $r->{total},     3, "compound excuse: 3 atomics";
  is $r->{satisfied}, 2, 'compound excuse: $a and $c satisfied';
  ok $r->{uncoverable}{1}, 'compound excuse: $b excused by uncoverable row';
  is_deeply $r->{missing}, [], "compound excuse: nothing missing";
}

# A column whose independence pair is achievable with more tests must stay
# missing even when another pair exists through an uncoverable row.  Covered
# (0,0) plus uncoverable (1,0) would pair $a, but the achievable rows (0,1)
# and (1,1) also pair it, so it is a test gap, not an excuse.
sub test_achievable_pair_stays_missing () {
  my $table = build_synthetic_table(
    '$a xor $b',
    ['$a', '$b'],
    [
      { inputs => [0, 0], result => 0 },
      { inputs => [1, 0], result => 1, covered => 0, uncoverable => 1 },
      { inputs => [0, 1], result => 1, covered => 0 },
      { inputs => [1, 1], result => 0, covered => 0 },
    ],
  );
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is_deeply $r->{missing}, ['$a', '$b'],
    "achievable pair: both columns are test gaps";
  is_deeply $r->{uncoverable}, {}, "achievable pair: nothing excused";
}

# The achievable probe uses the same masking fallback as the covered probe: a
# coupled column pairable among achievable rows stays missing even though an
# uncoverable row could also pair it.
sub test_coupled_achievable_pair_stays_missing () {
  my $table = build_synthetic_table(
    '($a && $b) || ($a && $c)',
    ['$a', '$b', '$a'],
    [
      { inputs => [1, 1, 1], result => 1 },
      { inputs => [0, 1, 0], result => 0, covered => 0 },
      { inputs => [0, 1, 1], result => 0, covered => 0, uncoverable => 1 },
    ],
  );
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is_deeply $r->{missing}, ['$a', '$b', '$a'],
    "coupled achievable: all columns are test gaps";
  is_deeply $r->{uncoverable}, {}, "coupled achievable: nothing excused";
}

# A pair formed from an uncoverable row and an achievable-but-untested row
# excuses nothing: the achievable row is still a test to write.  Once it is
# covered the column becomes excused (test_uncoverable_row_excuses_column).
sub test_uncoverable_pair_needs_covered_row () {
  my $table = build_synthetic_table(
    '$a && $b',
    ['$a', '$b'],
    [
      { inputs => [0, "X"], result => 0 },
      { inputs => [1, 0],   result => 0, covered => 0, uncoverable => 1 },
      { inputs => [1, 1],   result => 1, covered => 0 },
    ],
  );
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is_deeply $r->{missing}, ['$a', '$b'],
    "mixed pair: both columns still missing";
  is_deeply $r->{uncoverable}, {}, "mixed pair: nothing excused";
}

# A decision that never executed with every outcome marked uncoverable - code
# inside a branch that cannot be taken - is fully excused, not missing.
sub test_all_uncoverable_never_run_stays_excused () {
  my @conditions = (mock_condition_unc(
    "Condition_and_3",
    [0, 0, 0],
    { type => "and_3", left => '$a', op => "&&", right => '$b' },
    [1, 1, 1],
  ));
  my ($table) = Devel::Cover::Condition_table->for_line(\@conditions);
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is $r->{satisfied}, 0, "never run: nothing satisfied";
  is_deeply $r->{missing}, [], "never run: nothing missing";
  is_deeply [sort keys $r->{uncoverable}->%*], [0, 1],
    "never run: both columns excused";
}

sub main () {
  test_api_keys;
  test_uncoverable_row_excuses_column;
  test_compound_inner_uncoverable_propagates;
  test_compound_outer_uncoverable_propagates;
  test_compound_uncoverable_excuses_column;
  test_no_pair_even_with_uncoverable_stays_missing;
  test_achievable_pair_stays_missing;
  test_coupled_achievable_pair_stays_missing;
  test_uncoverable_pair_needs_covered_row;
  test_all_uncoverable_never_run_stays_excused;
  test_const_right_collapsed_observed_vectors;
  test_const_right_or_operator;
  test_const_right_compound_left_observed_vectors;
  test_and_satisfying;
  test_and_missing;
  test_or_satisfying;
  test_or_missing;
  test_and_x_pairs_with_concrete;
  test_or_x_pairs_with_concrete;
  test_and_concrete_only_pair;
  test_or_concrete_only_pair;
  test_masking_fires_when_coupled;
  test_masking_does_not_fire_when_uncoupled;
  test_x_as_second_argument;
  test_missing_empty_when_all_satisfied;
  test_missing_lists_unsatisfied_columns;
  test_missing_lists_all_columns;
  test_missing_preserves_coupled_columns;
  test_no_phantom_rows_in_worked_example;
  done_testing;
}

main;

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

sub test_api_shape () {
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
# coupled-condition behaviour: real Condition_table construction does not
# normally produce label collisions, but the analyser must still handle them.
sub build_synthetic_table ($expr, $labels, $rows) {
  my @row_objects = map {
    Devel::Cover::Condition_table::Row->new(
      inputs  => $_->{inputs},
      result  => $_->{result},
      covered => $_->{covered} // 1,
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
# `_concrete_differs` and `_sca_agrees` only see X as their first argument
# in normal runs.  This synthetic ordering puts the X-row second and
# exercises the X short-circuit on the second argument in both helpers.
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
# independence pairs for `$is_owner` and `$is_admin`, leaving `$unlocked` as
# the only atomic without a pair.  SCA MC/DC: 2/3 satisfied, missing
# `$unlocked`.  Without observed-vectors, `Condition_table::for_line`
# synthesises composite rows by cross-product, producing a phantom (T,F,F)
# covered=1 row that lets the analyser build a spurious pair for `$unlocked`.
# Threading observed-vectors through is what blocks the phantom: rows are
# marked covered iff their input vector was actually executed.
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
  # Outer || is the root (index 1); decision_inputs is populated only at
  # root entries.
  my @observed = (
    undef,
    {
      "1|1|X" => 1,    # (T,T,X) - $is_admin not evaluated
      "1|0|1" => 1,    # (T,F,T)
      "0|X|1" => 1,    # (F,X,T) - $unlocked not evaluated
      "0|X|0" => 1,    # (F,X,F)
    },
  );
  my ($table) = Devel::Cover::Condition_table->for_line(
    \@conditions, \@observed,
  );
  my $r = Devel::Cover::Mcdc::Analyser->analyse($table);
  is $r->{total},     3, "worked example: 3 atomics";
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

sub main () {
  test_api_shape;
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

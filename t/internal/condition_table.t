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

use Test::More import => [qw( done_testing is is_deeply like ok unlike )];

use Devel::Cover::Condition_table ();

# Build a mock condition object: blessed arrayref matching the structure that
# Devel::Cover produces.
#   [0] = arrayref of hit counts per path
#   [1] = hashref with {type, left, op, right}
sub mock_condition ($class, $hits, $info) {
  bless [$hits, $info], "Devel::Cover::$class"
}

# Single and_3: $a && $b
# Paths: !l, l&&!r, l&&r
# Coverage: !l hit, l&&!r not hit, l&&r hit
sub test_single_and3 () {
  my @conditions = (mock_condition(
    "Condition_and_3",
    [1, 0, 1],
    { type => "and_3", left => '$a', op => "&&", right => '$b' },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "single and_3 produces one table";

  my $t = $tables[0];
  is $t->expr, '$a && $b', "expression text";

  my @rows = $t->rows;
  is @rows, 3, "and_3 has three rows";

  # Sort rows by inputs for deterministic comparison
  @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } @rows;

  # Row: A=0 B=X -> result 0, covered (path !l was hit)
  is_deeply $rows[0]->inputs, [0, "X"], "row 0 inputs";
  is $rows[0]->result, 0, "row 0 result";
  ok $rows[0]->covered, "row 0 covered";

  # Row: A=1 B=0 -> result 0, not covered (path l&&!r not hit)
  is_deeply $rows[1]->inputs, [1, 0], "row 1 inputs";
  is $rows[1]->result, 0, "row 1 result";
  ok !$rows[1]->covered, "row 1 not covered";

  # Row: A=1 B=1 -> result 1, covered (path l&&r was hit)
  is_deeply $rows[2]->inputs, [1, 1], "row 2 inputs";
  is $rows[2]->result, 1, "row 2 result";
  ok $rows[2]->covered, "row 2 covered";
}

# Single or_3: $a || $b
# Paths: l, !l&&r, !l&&!r
# Coverage: l not hit, !l&&r hit, !l&&!r not hit
sub test_single_or3 () {
  my @conditions = (mock_condition(
    "Condition_or_3",
    [0, 1, 0],
    { type => "or_3", left => '$a', op => "||", right => '$b' },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "single or_3 produces one table";

  my $t    = $tables[0];
  my @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $t->rows;

  # Row: A=0 B=0 -> result 0, not covered
  is_deeply $rows[0]->inputs, [0, 0], "or3 row 0 inputs";
  is $rows[0]->result, 0, "or3 row 0 result";
  ok !$rows[0]->covered, "or3 row 0 not covered";

  # Row: A=0 B=1 -> result 1, covered
  is_deeply $rows[1]->inputs, [0, 1], "or3 row 1 inputs";
  is $rows[1]->result, 1, "or3 row 1 result";
  ok $rows[1]->covered, "or3 row 1 covered";

  # Row: A=1 B=X -> result 1, not covered
  is_deeply $rows[2]->inputs, [1, "X"], "or3 row 2 inputs";
  is $rows[2]->result, 1, "or3 row 2 result";
  ok !$rows[2]->covered, "or3 row 2 not covered";
}

# and_2: $a && constant (right is constant, only 2 paths: l, !l)
sub test_single_and2 () {
  my @conditions = (mock_condition(
    "Condition_and_2", [1, 0],
    { type => "and_2", left => '$a', op => "&&", right => "1" },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "and_2 produces one table";

  my @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $tables[0]->rows;
  is @rows, 2, "and_2 has two rows";

  is_deeply $rows[0]->inputs, [0], "and_2 row 0 inputs";
  ok $rows[0]->covered, "and_2 row 0 covered";

  is_deeply $rows[1]->inputs, [1], "and_2 row 1 inputs";
  ok !$rows[1]->covered, "and_2 row 1 not covered";
}

# or_2: $a || constant (2 paths: l, !l)
sub test_single_or2 () {
  my @conditions = (mock_condition(
    "Condition_or_2", [1, 1],
    { type => "or_2", left => '$a', op => "||", right => "0" },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "or_2 produces one table";

  my @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $tables[0]->rows;
  is @rows, 2, "or_2 has two rows";
  ok $rows[0]->covered, "or_2 row 0 covered";
  ok $rows[1]->covered, "or_2 row 1 covered";
}

# xor_4: $a xor $b (4 paths)
sub test_single_xor4 () {
  my @conditions = (mock_condition(
    "Condition_xor_4",
    [0, 1, 1, 0],
    { type => "xor_4", left => '$a', op => "xor", right => '$b' },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "xor_4 produces one table";

  my @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $tables[0]->rows;
  is @rows, 4, "xor_4 has four rows";

  # 0,0 -> 0, not covered
  is_deeply $rows[0]->inputs, [0, 0], "xor row 0 inputs";
  is $rows[0]->result, 0, "xor row 0 result";
  ok !$rows[0]->covered, "xor row 0 not covered";

  # 0,1 -> 1, covered
  is_deeply $rows[1]->inputs, [0, 1], "xor row 1 inputs";
  is $rows[1]->result, 1, "xor row 1 result";
  ok $rows[1]->covered, "xor row 1 covered";

  # 1,0 -> 1, covered
  is_deeply $rows[2]->inputs, [1, 0], "xor row 2 inputs";
  is $rows[2]->result, 1, "xor row 2 result";
  ok $rows[2]->covered, "xor row 2 covered";

  # 1,1 -> 0, not covered
  is_deeply $rows[3]->inputs, [1, 1], "xor row 3 inputs";
  is $rows[3]->result, 0, "xor row 3 result";
  ok !$rows[3]->covered, "xor row 3 not covered";
}

# Composite: $a || $b && $c
# Two conditions on the same line:
#   and_3: left=$b, op=&&, right=$c  (expr = "$b && $c")
#   or_3:  left=$a, op=||, right="$b && $c"
# The or_3's right operand matches the and_3's expression, so they form a tree:
# $a || ($b && $c)
#
# Truth table should have 4 rows:
#   A=0 B=0 C=X -> 0  (or: !l&&!r, and: !l)
#   A=0 B=1 C=0 -> 0  (or: !l&&!r, and: l&&!r)
#   A=0 B=1 C=1 -> 1  (or: !l&&r,  and: l&&r)
#   A=1 B=X C=X -> 1  (or: l)
#
# Coverage: all paths hit except and_3 path l&&!r
sub test_composite_or_and () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 0, 1],
      { type => "and_3", left => '$b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_or_3",
      [1, 1, 1],
      { type => "or_3", left => '$a', op => "||", right => '$b && $c' },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "composite produces one merged table";

  my $t = $tables[0];
  is $t->expr, '$a || $b && $c', "composite expression text";

  my @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $t->rows;
  is @rows, 4, "composite has four rows";

  # A=0 B=0 C=X -> 0, covered (or !l&&!r hit, and !l hit)
  is_deeply $rows[0]->inputs, [0, 0, "X"], "comp row 0 inputs";
  is $rows[0]->result, 0, "comp row 0 result";
  ok $rows[0]->covered, "comp row 0 covered";

  # A=0 B=1 C=0 -> 0, NOT covered (and l&&!r not hit)
  is_deeply $rows[1]->inputs, [0, 1, 0], "comp row 1 inputs";
  is $rows[1]->result, 0, "comp row 1 result";
  ok !$rows[1]->covered, "comp row 1 not covered";

  # A=0 B=1 C=1 -> 1, covered (or !l&&r hit, and l&&r hit)
  is_deeply $rows[2]->inputs, [0, 1, 1], "comp row 2 inputs";
  is $rows[2]->result, 1, "comp row 2 result";
  ok $rows[2]->covered, "comp row 2 covered";

  # A=1 B=X C=X -> 1, covered (or l hit)
  is_deeply $rows[3]->inputs, [1, "X", "X"], "comp row 3 inputs";
  is $rows[3]->result, 1, "comp row 3 result";
  ok $rows[3]->covered, "comp row 3 covered";
}

# Deep composite: $a && $b && $c && $d (4 variables, 3 conditions)
# Perl builds this as a left-associative chain:
#   and_3: $a && $b           (expr = "$a && $b")
#   and_3: "$a && $b" && $c   (expr = "$a && $b && $c")
#   and_3: "$a && $b && $c" && $d
sub test_deep_and_chain () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 1, 1],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_and_3",
      [1, 0, 1],
      { type => "and_3", left => '$a && $b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_and_3",
      [1, 1, 0], {
        type  => "and_3",
        left  => '$a && $b && $c',
        op    => "&&",
        right => '$d',
      },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "deep chain produces one table";

  my $t = $tables[0];
  is $t->expr, '$a && $b && $c && $d', "deep chain expression";

  my @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $t->rows;

  # Expected rows for $a && $b && $c && $d:
  #   0 X X X -> 0  (first and !l)
  #   1 0 X X -> 0  (first and l&&!r)
  #   1 1 0 X -> 0  (second and l&&!r)
  #   1 1 1 0 -> 0  (third and l&&!r)
  #   1 1 1 1 -> 1  (third and l&&r)
  is @rows, 5, "deep chain has five rows";

  # A=0: first and !l hit -> covered
  is_deeply $rows[0]->inputs, [0, "X", "X", "X"], "deep row 0";
  ok $rows[0]->covered, "deep row 0 covered";

  # A=1 B=0: first and l&&!r hit -> covered
  is_deeply $rows[1]->inputs, [1, 0, "X", "X"], "deep row 1";
  ok $rows[1]->covered, "deep row 1 covered";

  # A=1 B=1 C=0: second and l&&!r NOT hit -> not covered
  is_deeply $rows[2]->inputs, [1, 1, 0, "X"], "deep row 2";
  ok !$rows[2]->covered, "deep row 2 not covered";

  # A=1 B=1 C=1 D=0: third and l&&!r hit -> covered
  is_deeply $rows[3]->inputs, [1, 1, 1, 0], "deep row 3";
  ok $rows[3]->covered, "deep row 3 covered";

  # A=1 B=1 C=1 D=1: third and l&&r NOT hit -> not covered
  is_deeply $rows[4]->inputs, [1, 1, 1, 1], "deep row 4";
  ok !$rows[4]->covered, "deep row 4 not covered";
}

# Multiple independent conditions on one line (e.g. two statements)
sub test_independent_conditions () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 0, 1],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_or_3",
      [1, 1, 0],
      { type => "or_3", left => '$x', op => "||", right => '$y' },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 2, "independent conditions produce two tables";

  my @exprs = sort map { $_->expr } @tables;
  is_deeply \@exprs, ['$a && $b', '$x || $y'], "both expressions present";
}

# Chain of $n atomics ($x1 && $x2 && ... && $xn): n-1 and_3 records whose left
# strings accumulate, matching how Devel::Cover records a chain.
sub chain_conditions ($n, $prefix) {
  my @atoms = map "\$$prefix$_", 1 .. $n;
  my @conditions;
  my $left = $atoms[0];
  for my $i (1 .. $n - 1) {
    push @conditions,
      mock_condition(
        "Condition_and_3",
        [1, 1, 1],
        { type => "and_3", left => $left, op => "&&", right => $atoms[$i] },
      );
    $left = "$left && $atoms[$i]";
  }
  @conditions
}

# A decision with more than 16 atomic conditions is too wide to analyse:
# for_line returns a stub table flagged too_wide, with labels (so consumers know
# the width) but no rows.
sub test_too_wide_decision () {
  my @conditions = chain_conditions(17, "a");

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "too wide: one table";

  my $t = $tables[0];
  ok $t->too_wide, "too wide: flagged";
  ok !$t->proven,  "too wide: not proven";

  my @rows = $t->rows;
  is @rows, 0, "too wide: no rows";

  my @labels = $t->labels;
  is @labels,  17, "too wide: labels carry the width";
  is $t->expr, join(" && ", map "\$a$_", 1 .. 17), "too wide: expr text";
}

# Exactly 16 atomic conditions is within the limit.
sub test_exactly_16_atomics () {
  my @conditions = chain_conditions(16, "a");

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "16 atomics: one table";
  ok !$tables[0]->too_wide, "16 atomics: not too wide";

  my @labels = $tables[0]->labels;
  is @labels, 16, "16 atomics: all labels present";

  my @rows = $tables[0]->rows;
  is @rows, 17, "16 atomics: rows built";
}

# The cap is per decision, not per line: two 10-atomic decisions sharing a line
# (18 condition records, more than the old per-line cap) must both be analysed.
sub test_two_decisions_one_line () {
  my @conditions = (chain_conditions(10, "a"), chain_conditions(10, "b"));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 2, "two decisions on one line: two tables";
  for my $t (@tables) {
    ok !$t->too_wide, "decision @{[$t->expr]} not too wide";
    my @rows = $t->rows;
    is @rows, 11, "decision @{[$t->expr]} rows built";
  }
}

# A too-wide decision and a narrow one on the same line: only the wide one
# becomes a stub.
sub test_wide_and_narrow_one_line () {
  my @conditions = (chain_conditions(17, "a"), chain_conditions(2, "b"));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 2, "wide+narrow: two tables";

  my ($wide)   = grep { $_->too_wide } @tables;
  my ($narrow) = grep { !$_->too_wide } @tables;
  ok $wide,   "wide+narrow: wide table flagged";
  ok $narrow, "wide+narrow: narrow table analysed";

  my @rows = $narrow ? $narrow->rows : ();
  is @rows, 3, "wide+narrow: narrow rows built";
}

# undef in hit counts (Devel::Cover can produce these)
sub test_undef_hits () {
  my @conditions = (mock_condition(
    "Condition_and_3",
    [undef, 0, 1],
    { type => "and_3", left => '$a', op => "&&", right => '$b' },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  my @rows   = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $tables[0]->rows;

  # undef counts as not hit
  ok !$rows[0]->covered, "undef hit treated as not covered";
  ok !$rows[1]->covered, "zero hit not covered";
  ok $rows[2]->covered,  "positive hit covered";
}

# Unknown condition type - _build_rows returns empty
sub test_unknown_type () {
  my @conditions = (mock_condition(
    "Condition", [1, 0],
    { type => "unknown", left => '$a', op => "??", right => '$b' },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "unknown type produces a table";

  my @rows = $tables[0]->rows;
  is @rows, 0, "unknown type table has no rows";
}

# Single-input condition with sub-expression: or_2 where left is a
# sub-expression with an uncovered path. This exercises the $row->covered &&
# $le->[1] branch where $row->covered is true but $le->[1] is false.
sub test_single_input_with_subexpr () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 0, 1],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_or_2", [1, 1],
      { type => "or_2", left => '$a && $b', op => "||", right => "0" },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "or_2 with sub-expr produces one table";

  my @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $tables[0]->rows;
  is @rows, 3, "or_2 with sub-expr has three rows";

  # A=0 B=X -> or_2 left=0 (result 0), and_3 !l path covered or_2 covered=1,
  # and_3 covered=1 -> covered
  is_deeply $rows[0]->inputs, [0, "X"], "subexpr row 0 inputs";
  ok $rows[0]->covered, "subexpr row 0 covered";

  # A=1 B=0 -> or_2 left=0 (result 0), and_3 l&&!r NOT covered or_2 covered=1,
  # and_3 covered=0 -> NOT covered
  is_deeply $rows[1]->inputs, [1, 0], "subexpr row 1 inputs";
  ok !$rows[1]->covered, "subexpr row 1 not covered (sub-expr uncovered)";

  # A=1 B=1 -> or_2 left=1 (result 1), and_3 l&&r covered or_2 covered=1, and_3
  # covered=1 -> covered
  is_deeply $rows[2]->inputs, [1, 1], "subexpr row 2 inputs";
  ok $rows[2]->covered, "subexpr row 2 covered";
}

# Labels: single and_3 has two leaf labels
sub test_labels_simple () {
  my @conditions = (mock_condition(
    "Condition_and_3",
    [1, 0, 1],
    { type => "and_3", left => '$a', op => "&&", right => '$b' },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is_deeply [$tables[0]->labels], ['$a', '$b'],
    "labels: simple and_3 has two leaf labels";
}

# Labels: composite $a || ($b && $c) has three leaf labels
sub test_labels_composite () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 0, 1],
      { type => "and_3", left => '$b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_or_3",
      [1, 1, 1],
      { type => "or_3", left => '$a', op => "||", right => '$b && $c' },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is_deeply [$tables[0]->labels], ['$a', '$b', '$c'],
    "labels: composite has three leaf labels";
}

# Labels: deep chain $a && $b && $c && $d
sub test_labels_deep_chain () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 1, 1],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_and_3",
      [1, 0, 1],
      { type => "and_3", left => '$a && $b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_and_3",
      [1, 1, 0], {
        type  => "and_3",
        left  => '$a && $b && $c',
        op    => "&&",
        right => '$d',
      },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is_deeply [$tables[0]->labels], ['$a', '$b', '$c', '$d'],
    "labels: deep chain has four leaf labels";
}

# Labels: boolean (single-input) condition
sub test_labels_boolean () {
  my @conditions = (mock_condition(
    "Condition_and_2", [1, 0],
    { type => "and_2", left => '$a', op => "&&", right => "1" },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is_deeply [$tables[0]->labels], ['$a'], "labels: boolean has one label";
}

# Labels: or_2 with sub-expression on left
sub test_labels_boolean_with_subexpr () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 0, 1],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_or_2", [1, 1],
      { type => "or_2", left => '$a && $b', op => "||", right => "0" },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is_deeply [$tables[0]->labels], ['$a', '$b'],
    "labels: boolean with sub-expr expands to leaf labels";
}

# short_expr: operator structure with letters
sub test_short_expr_simple () {
  my @conditions = (mock_condition(
    "Condition_and_3",
    [1, 0, 1],
    { type => "and_3", left => '$a', op => "&&", right => '$b' },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is $tables[0]->short_expr, "A && B", "short_expr: simple and_3";
}

sub test_short_expr_composite () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 0, 1],
      { type => "and_3", left => '$b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_or_3",
      [1, 1, 1],
      { type => "or_3", left => '$a', op => "||", right => '$b && $c' },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is $tables[0]->short_expr, "A || B && C", "short_expr: composite or/and";
}

sub test_short_expr_deep_chain () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 1, 1],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_and_3",
      [1, 0, 1],
      { type => "and_3", left => '$a && $b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_and_3",
      [1, 1, 0], {
        type  => "and_3",
        left  => '$a && $b && $c',
        op    => "&&",
        right => '$d',
      },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is $tables[0]->short_expr, "A && B && C && D", "short_expr: deep chain";
}

sub test_short_expr_boolean () {
  my @conditions = (mock_condition(
    "Condition_or_2", [1, 1],
    { type => "or_2", left => '$a', op => "||", right => "0" },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is $tables[0]->short_expr, "A", "short_expr: boolean";
}

# Nested mixed operators: @a == 1 || (@a == 2 && $b && $c) produces three
# conditions that should merge into one 4-variable table. The metadata
# left/right fields must match _expr() output of child conditions (no spurious
# parentheses).
sub test_nested_mixed_operators () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 1, 1],
      { type => "and_3", left => '@a == 2', op => "and", right => '$b' },
    ),
    mock_condition(
      "Condition_and_3",
      [1, 0, 1], {
        type  => "and_3",
        left  => '@a == 2 and $b',
        op    => "and",
        right => '$c',
      },
    ),
    mock_condition(
      "Condition_or_3",
      [0, 0, 1], {
        type  => "or_3",
        left  => '@a == 1',
        op    => "or",
        right => '@a == 2 and $b and $c',
      },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "nested: produces one merged table";

  my $t = $tables[0];
  is $t->short_expr, "A or B and C and D",
    "nested: short_expr has four variables";
  is_deeply [$t->labels], ['@a == 1', '@a == 2', '$b', '$c'],
    "nested: labels resolve through tree";

  my @rows = $t->rows;
  is @rows, 5, "nested: merged table has five rows";
}

# Extra addr fields in metadata should be ignored when not used for linking.
# This is a baseline test to confirm no regression.
sub test_addr_fields_passthrough () {
  my @conditions = (mock_condition(
    "Condition_and_3",
    [1, 0, 1], {
      type       => "and_3",
      left       => '$a',
      op         => "&&",
      right      => '$b',
      addr       => 100,
      left_addr  => 200,
      right_addr => 300,
    },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables,          1,          "addr passthrough: one table";
  is $tables[0]->expr, '$a && $b', "addr passthrough: expr unchanged";

  my @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $tables[0]->rows;
  is @rows, 3, "addr passthrough: three rows";
  ok $rows[0]->covered,  "addr passthrough: row 0 covered";
  ok !$rows[1]->covered, "addr passthrough: row 1 not covered";
  ok $rows[2]->covered,  "addr passthrough: row 2 covered";
}

# Addr-based linking: parent's right string is deliberately wrong but right_addr
# matches child's addr.  Tree linking should still work.
sub test_addr_linking () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 0, 1], {
        type  => "and_3",
        left  => '$b',
        op    => "&&",
        right => '$c',
        addr  => 42,
      },
    ),
    mock_condition(
      "Condition_or_3",
      [1, 1, 0], {
        type       => "or_3",
        left       => '$a',
        op         => "||",
        right      => "MISMATCH",
        addr       => 99,
        right_addr => 42,
      },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "addr linking: one merged table";
  is $tables[0]->short_expr, "A || B && C",
    "addr linking: short_expr shows merged tree";
  is_deeply [$tables[0]->labels], ['$a', '$b', '$c'],
    "addr linking: labels from child condition";
}

# Deep chain with addr linking: string left values are wrong but left_addr
# values chain correctly.
sub test_addr_linking_deep_chain () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 1, 1], {
        type  => "and_3",
        left  => '$a',
        op    => "&&",
        right => '$b',
        addr  => 10,
      },
    ),
    mock_condition(
      "Condition_and_3",
      [1, 0, 1], {
        type      => "and_3",
        left      => "WRONG1",
        op        => "&&",
        right     => '$c',
        addr      => 20,
        left_addr => 10,
      },
    ),
    mock_condition(
      "Condition_and_3",
      [1, 1, 0], {
        type      => "and_3",
        left      => "WRONG2",
        op        => "&&",
        right     => '$d',
        addr      => 30,
        left_addr => 20,
      },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "addr deep chain: one table";
  is_deeply [$tables[0]->labels], ['$a', '$b', '$c', '$d'],
    "addr deep chain: four leaf labels";
  is $tables[0]->short_expr, "A && B && C && D", "addr deep chain: short_expr";

  my @rows = $tables[0]->rows;
  is @rows, 5, "addr deep chain: five rows";
}

# Fallback to string matching when addr fields are absent.
sub test_addr_fallback_to_string () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 0, 1],
      { type => "and_3", left => '$b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_or_3",
      [1, 1, 0], {
        type       => "or_3",
        left       => '$a',
        op         => "||",
        right      => '$b && $c',
        right_addr => undef,
      },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "addr fallback: string match still works";
  is_deeply [$tables[0]->labels], ['$a', '$b', '$c'],
    "addr fallback: labels from string-matched child";
}

# Addr takes priority over conflicting string match.
sub test_addr_overrides_string () {
  my @conditions = (
    # X: addr 10, _expr = "$b && $c"
    mock_condition(
      "Condition_and_3",
      [1, 0, 1], {
        type  => "and_3",
        left  => '$b',
        op    => "&&",
        right => '$c',
        addr  => 10,
      },
    ),
    # Y: addr 20, _expr = "$d && $e" (matches parent's right by string)
    mock_condition(
      "Condition_and_3",
      [1, 1, 0], {
        type  => "and_3",
        left  => '$d',
        op    => "&&",
        right => '$e',
        addr  => 20,
      },
    ),
    # Parent: right string matches Y, but right_addr points to X
    mock_condition(
      "Condition_or_3",
      [0, 1, 1], {
        type       => "or_3",
        left       => '$a',
        op         => "||",
        right      => '$d && $e',
        addr       => 30,
        right_addr => 10,
      },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);

  # Parent should link to X (addr 10), not Y (addr 20, string match)
  my ($root) = grep { $_->expr =~ /\|\|/ } @tables;
  is_deeply [$root->labels], ['$a', '$b', '$c'],
    "addr priority: links to addr match, not string match";
}

# Negated sub-expression: $a || not($b && $c)
# The compiler can transform !X && !Y into not(X || Y) via DeMorgan.
# The right operand of the outer or is negated, so when the outer or sees
# right=1, it means not(and_result)=1, i.e. and_result=0.
# _expand_operand must invert $val for negated sub-expressions.
#
# or_3 spec:  [1,X]->1, [0,1]->1, [0,0]->0
# and_3 spec: [0,X]->0, [1,0]->0, [1,1]->1
#
# Correct expansion with right_negated:
#   A=1 B=X C=X -> 1  (left=1, right=X)
#   A=0 B=0 C=X -> 1  (left=0, right=1 -> need and=0 -> B=0)
#   A=0 B=1 C=0 -> 1  (left=0, right=1 -> need and=0 -> B=1,C=0)
#   A=0 B=1 C=1 -> 0  (left=0, right=0 -> need and=1 -> B=1,C=1)
# When observed-vector data is supplied, for_line marks rows covered iff their
# input vector matches an observed key.  Synthesised rows that were never
# observed are still rendered for the truth-table display but carry covered=0 so
# the analyser ignores them.  Without observed-vectors, cross-product synthesis
# can produce a composite row marked covered=1 even though the combined input
# was never executed.
sub test_observed_vectors_override_synthesis () {
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

  # Worked-example: four tests yield exactly these four input vectors. Outer ||
  # is the root (index 1 in @conditions); decision_inputs is populated only at
  # root entries.
  my @observed = (
    undef, {
      "1|1|X" => 1,  # (T,T,X) - $is_admin not evaluated, short-circuit
      "1|0|1" => 1,  # (T,F,T)
      "0|X|1" => 1,  # (F,X,T) - $unlocked not evaluated
      "0|X|0" => 1,  # (F,X,F)
    },
  );

  my ($table)
    = Devel::Cover::Condition_table->for_line(\@conditions, \@observed);

  my %covered;
  for my $row ($table->rows) {
    $covered{ join "|", $row->inputs->@* } = $row->covered ? 1 : 0;
  }

  is $covered{"1|1|X"}, 1, "observed (T,T,X) covered";
  is $covered{"1|0|1"}, 1, "observed (T,F,T) covered";
  is $covered{"0|X|1"}, 1, "observed (F,X,T) covered";
  is $covered{"0|X|0"}, 1, "observed (F,X,F) covered";

  ok exists $covered{"1|0|0"},
    "synthesised phantom row still rendered for display";
  is $covered{"1|0|0"}, 0,
    "synthesised phantom row marked covered=0 (never executed)";
}

# xor does not short-circuit, so observed vectors are always 2 concrete values
# (no X).  Synthesis with all-1 hits would mark every row covered;
# observed-vectors restrict coverage to vectors actually executed.
sub test_observed_vectors_xor () {
  my @conditions = (mock_condition(
    "Condition_xor_4",
    [1, 1, 1, 1],
    { type => "xor_4", left => '$a', op => "xor", right => '$b' },
  ));

  my @observed = ({ "0|1" => 1, "1|0" => 1 });

  my ($t) = Devel::Cover::Condition_table->for_line(\@conditions, \@observed);

  my %covered;
  for my $row ($t->rows) {
    $covered{ join "|", $row->inputs->@* } = $row->covered ? 1 : 0;
  }

  is $covered{"0|1"}, 1, "xor: observed (0,1) covered";
  is $covered{"1|0"}, 1, "xor: observed (1,0) covered";
  is $covered{"0|0"}, 0, "xor: unobserved (0,0) not covered";
  is $covered{"1|1"}, 0, "xor: unobserved (1,1) not covered";
}

# A recorded vector narrower than the rows means the recorder and the table
# disagreed about columns.  Such a key must be skipped with a warning naming the
# vector, not wipe the valid keys' coverage or leak uninitialized-value
# warnings.
sub test_short_observed_vector_ignored () {
  my @conditions = (mock_condition(
    "Condition_and_3",
    [1, 1, 1],
    { type => "and_3", left => '$a', op => "&&", right => '$b' },
  ));

  my @observed = ({ "1|1" => 1, "0|X" => 1, "1" => 1 });

  my $err = "";
  my ($t) = do {
    open my $save, ">&", \*STDERR or die "Cannot dup STDERR: $!";
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">", \$err or die "Cannot redirect STDERR: $!";
    my @r = Devel::Cover::Condition_table->for_line(\@conditions, \@observed);
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">&", $save or die "Cannot restore STDERR: $!";
    @r
  };

  my %covered;
  $covered{ join "|", $_->inputs->@* } = $_->covered ? 1 : 0 for $t->rows;

  is $covered{"1|1"}, 1, "short key: valid observed key still covers its row";
  is $covered{"0|X"}, 1, "short key: short-circuit key still covers its row";
  unlike $err, qr/[Uu]ninitialized/, "short key: no uninitialized warnings";
  like $err, qr|Ignoring short MC/DC vector "1" for \$a && \$b|,
    "short key: warning names the vector and the expression";
}

# Deep chain $a && $b && $c && $d: three logops, four atomics, five synthesised
# rows.  Observe only the all-true and outermost-false vectors; the three
# intermediate short-circuit rows must read covered=0.
sub test_observed_vectors_deep_chain () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 1, 1],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_and_3",
      [1, 1, 1],
      { type => "and_3", left => '$a && $b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_and_3",
      [1, 1, 1], {
        type  => "and_3",
        left  => '$a && $b && $c',
        op    => "&&",
        right => '$d',
      },
    ),
  );

  # Root is index 2 (the outermost &&).  Inner conditions hold no
  # observed-vector data.
  my @observed = (undef, undef, { "1|1|1|1" => 1, "0|X|X|X" => 1 });

  my ($t) = Devel::Cover::Condition_table->for_line(\@conditions, \@observed);

  my %covered;
  for my $row ($t->rows) {
    $covered{ join "|", $row->inputs->@* } = $row->covered ? 1 : 0;
  }

  is $covered{"1|1|1|1"}, 1, "deep: observed (1,1,1,1) covered";
  is $covered{"0|X|X|X"}, 1, "deep: observed (0,X,X,X) covered";
  is $covered{"1|0|X|X"}, 0, "deep: phantom (1,0,X,X) not covered";
  is $covered{"1|1|0|X"}, 0, "deep: phantom (1,1,0,X) not covered";
  is $covered{"1|1|1|0"}, 0, "deep: phantom (1,1,1,0) not covered";
}

# Mixed-type chain ($a && $b) || ($c && $d): root is the ||, with two inner &&
# children.  Synthesis produces seven rows; four are observed at runtime, three
# are phantom.
sub test_observed_vectors_mixed_chain () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 1, 1],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_and_3",
      [1, 1, 1],
      { type => "and_3", left => '$c', op => "&&", right => '$d' },
    ),
    mock_condition(
      "Condition_or_3",
      [1, 1, 1], {
        type  => "or_3",
        left  => '$a && $b',
        op    => "||",
        right => '$c && $d',
      },
    ),
  );

  # Vectors that arise from these four calls:
  #   (1,1,?,?) - left true, right not evaluated         -> 1|1|X|X
  #   (1,0,1,1) - left false via right; right both true  -> 1|0|1|1
  #   (0,?,0,?) - both halves short-circuit at left      -> 0|X|0|X
  #   (1,0,1,0) - left false via right; right false too  -> 1|0|1|0
  my @observed = (
    undef, undef,
    { "1|1|X|X" => 1, "1|0|1|1" => 1, "0|X|0|X" => 1, "1|0|1|0" => 1 },
  );

  my ($t) = Devel::Cover::Condition_table->for_line(\@conditions, \@observed);

  my %covered;
  for my $row ($t->rows) {
    $covered{ join "|", $row->inputs->@* } = $row->covered ? 1 : 0;
  }

  is $covered{"1|1|X|X"}, 1, "mixed: observed (1,1,X,X) covered";
  is $covered{"1|0|1|1"}, 1, "mixed: observed (1,0,1,1) covered";
  is $covered{"0|X|0|X"}, 1, "mixed: observed (0,X,0,X) covered";
  is $covered{"1|0|1|0"}, 1, "mixed: observed (1,0,1,0) covered";

  ok exists $covered{"0|X|1|1"}, "mixed: phantom row still rendered";
  is $covered{"0|X|1|1"}, 0, "mixed: phantom (0,X,1,1) not covered";
}

# Observed-vectors are indexed parallel to @conditions.  for_line reads
# $observed->[$i] only at root indices; data placed at non-root indices is
# silently dropped.  This covers the contract _derive_mcdc and the runtime XS
# layer rely on (vectors are recorded at decision roots).
sub test_observed_vectors_indexed_at_root () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 1, 1],
      { type => "and_3", left => '$b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_or_3",
      [1, 1, 1],
      { type => "or_3", left => '$a', op => "||", right => '$b && $c' },
    ),
  );

  # (a) Observed at non-root slot is ignored; synthesis applies and marks all
  # four rows covered (all hit-counts are 1).
  my @at_non_root = ({ "1|1|X" => 1 }, undef);
  my ($t1)
    = Devel::Cover::Condition_table->for_line(\@conditions, \@at_non_root);
  my %cov1;
  for my $row ($t1->rows) {
    $cov1{ join "|", $row->inputs->@* } = $row->covered ? 1 : 0;
  }
  is $cov1{"1|X|X"}, 1, "non-root slot ignored: synthesis (1,X,X) covered";
  is $cov1{"0|0|X"}, 1, "non-root slot ignored: synthesis (0,0,X) covered";
  is $cov1{"0|1|1"}, 1, "non-root slot ignored: synthesis (0,1,1) covered";

  # (b) Observed at root slot drives coverage.  Only the listed vector is
  # covered; the other rows render as phantoms.
  my @at_root = (undef, { "1|X|X" => 1 });
  my ($t2) = Devel::Cover::Condition_table->for_line(\@conditions, \@at_root);
  my %cov2;
  for my $row ($t2->rows) {
    $cov2{ join "|", $row->inputs->@* } = $row->covered ? 1 : 0;
  }
  is $cov2{"1|X|X"}, 1, "root slot applied: (1,X,X) covered";
  is $cov2{"0|0|X"}, 0, "root slot applied: (0,0,X) not observed";
  is $cov2{"0|1|0"}, 0, "root slot applied: (0,1,0) not observed";
  is $cov2{"0|1|1"}, 0, "root slot applied: (0,1,1) not observed";
}

sub test_negated_subexpr () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 0, 1], {
        type  => "and_3",
        left  => '$b',
        op    => "&&",
        right => '$c',
        addr  => 42,
      },
    ),
    mock_condition(
      "Condition_or_3",
      [1, 1, 1], {
        type          => "or_3",
        left          => '$a',
        op            => "||",
        right         => 'not($b && $c)',
        addr          => 99,
        right_addr    => 42,
        right_negated => 1,
      },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "negated: one merged table";

  my $t = $tables[0];
  is $t->short_expr, "A || not(B && C)", "negated: heading shows not(...)";

  my @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $t->rows;
  is @rows, 4, "negated: four rows";

  # A=0 B=0 C=X -> 1 (not(and=0)=1, or: left=0,right=1 -> 1)
  is_deeply $rows[0]->inputs, [0, 0, "X"], "neg row 0 inputs";
  is $rows[0]->result, 1, "neg row 0 result";
  ok $rows[0]->covered, "neg row 0 covered";

  # A=0 B=1 C=0 -> 1 (not(and=0)=1, or: left=0,right=1 -> 1)
  is_deeply $rows[1]->inputs, [0, 1, 0], "neg row 1 inputs";
  is $rows[1]->result, 1, "neg row 1 result";
  ok !$rows[1]->covered, "neg row 1 not covered (and path l&&!r not hit)";

  # A=0 B=1 C=1 -> 0 (not(and=1)=0, or: left=0,right=0 -> 0)
  is_deeply $rows[2]->inputs, [0, 1, 1], "neg row 2 inputs";
  is $rows[2]->result, 0, "neg row 2 result";
  ok $rows[2]->covered, "neg row 2 covered";

  # A=1 B=X C=X -> 1 (or: left=1 -> 1)
  is_deeply $rows[3]->inputs, [1, "X", "X"], "neg row 3 inputs";
  is $rows[3]->result, 1, "neg row 3 result";
  ok $rows[3]->covered, "neg row 3 covered";
}

# A single logop's per-outcome hit counts ARE its observed inputs, so its
# synthesised rows are trustworthy even with no observed vectors.
sub test_proven_single_logop () {
  my @conditions = (mock_condition(
    "Condition_and_3",
    [1, 0, 1],
    { type => "and_3", left => '$a', op => "&&", right => '$b' },
  ));
  my ($t) = Devel::Cover::Condition_table->for_line(\@conditions);
  ok $t->proven, "single logop is proven without observed vectors";
}

# Worked example: $a || ($b && $c).  Without observed vectors the composite rows
# are a synthesised cross-product whose co-occurrence was never demonstrated, so
# the table is not proven.
sub _worked_example_conditions () { (
  mock_condition(
    "Condition_and_3",
    [1, 0, 1],
    { type => "and_3", left => '$b', op => "&&", right => '$c' },
  ),
  mock_condition(
    "Condition_or_3",
    [1, 1, 1],
    { type => "or_3", left => '$a', op => "||", right => '$b && $c' },
  ),
) }

sub test_proven_compound_synthesised () {
  my @conditions = _worked_example_conditions;
  my ($t) = Devel::Cover::Condition_table->for_line(\@conditions);
  ok !$t->proven, "compound decision is not proven without observed vectors";
}

sub test_proven_compound_observed () {
  my @conditions = _worked_example_conditions;
  my @observed   = (undef, { "1|X|X" => 1, "0|1|1" => 1, "0|0|X" => 1 });
  my ($t) = Devel::Cover::Condition_table->for_line(\@conditions, \@observed);
  ok $t->proven, "compound decision is proven once observed vectors apply";
}

sub main () {
  test_proven_single_logop;
  test_proven_compound_synthesised;
  test_proven_compound_observed;
  test_single_and3;
  test_single_or3;
  test_single_and2;
  test_single_or2;
  test_single_xor4;
  test_composite_or_and;
  test_deep_and_chain;
  test_independent_conditions;
  test_too_wide_decision;
  test_exactly_16_atomics;
  test_two_decisions_one_line;
  test_wide_and_narrow_one_line;
  test_undef_hits;
  test_unknown_type;
  test_single_input_with_subexpr;
  test_labels_simple;
  test_labels_composite;
  test_labels_deep_chain;
  test_labels_boolean;
  test_labels_boolean_with_subexpr;
  test_short_expr_simple;
  test_short_expr_composite;
  test_short_expr_deep_chain;
  test_short_expr_boolean;
  test_nested_mixed_operators;
  test_addr_fields_passthrough;
  test_addr_linking;
  test_addr_linking_deep_chain;
  test_addr_fallback_to_string;
  test_addr_overrides_string;
  test_observed_vectors_override_synthesis;
  test_observed_vectors_xor;
  test_short_observed_vector_ignored;
  test_observed_vectors_deep_chain;
  test_observed_vectors_mixed_chain;
  test_observed_vectors_indexed_at_root;
  test_negated_subexpr;
  done_testing;
}

main;

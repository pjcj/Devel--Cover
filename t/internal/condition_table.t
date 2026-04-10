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

use Test::More import => [ qw( done_testing is is_deeply ok ) ];

use Devel::Cover::Condition_table ();

# Build a mock condition object: blessed arrayref matching the structure
# that Devel::Cover produces.
#   [0] = arrayref of hit counts per path
#   [1] = hashref with {type, left, op, right}
sub mock_condition ($class, $hits, $info) {
  bless [ $hits, $info ], "Devel::Cover::$class"
}

# Single and_3: $a && $b
# Paths: !l, l&&!r, l&&r
# Coverage: !l hit, l&&!r not hit, l&&r hit
sub test_single_and3 () {
  my @conditions = (mock_condition(
    "Condition_and_3",
    [ 1, 0, 1 ],
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
  is_deeply $rows[0]->inputs, [ 0, "X" ], "row 0 inputs";
  is $rows[0]->result, 0, "row 0 result";
  ok $rows[0]->covered, "row 0 covered";

  # Row: A=1 B=0 -> result 0, not covered (path l&&!r not hit)
  is_deeply $rows[1]->inputs, [ 1, 0 ], "row 1 inputs";
  is $rows[1]->result, 0, "row 1 result";
  ok !$rows[1]->covered, "row 1 not covered";

  # Row: A=1 B=1 -> result 1, covered (path l&&r was hit)
  is_deeply $rows[2]->inputs, [ 1, 1 ], "row 2 inputs";
  is $rows[2]->result, 1, "row 2 result";
  ok $rows[2]->covered, "row 2 covered";
}

# Single or_3: $a || $b
# Paths: l, !l&&r, !l&&!r
# Coverage: l not hit, !l&&r hit, !l&&!r not hit
sub test_single_or3 () {
  my @conditions = (mock_condition(
    "Condition_or_3",
    [ 0, 1, 0 ],
    { type => "or_3", left => '$a', op => "||", right => '$b' },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "single or_3 produces one table";

  my $t    = $tables[0];
  my @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $t->rows;

  # Row: A=0 B=0 -> result 0, not covered
  is_deeply $rows[0]->inputs, [ 0, 0 ], "or3 row 0 inputs";
  is $rows[0]->result, 0, "or3 row 0 result";
  ok !$rows[0]->covered, "or3 row 0 not covered";

  # Row: A=0 B=1 -> result 1, covered
  is_deeply $rows[1]->inputs, [ 0, 1 ], "or3 row 1 inputs";
  is $rows[1]->result, 1, "or3 row 1 result";
  ok $rows[1]->covered, "or3 row 1 covered";

  # Row: A=1 B=X -> result 1, not covered
  is_deeply $rows[2]->inputs, [ 1, "X" ], "or3 row 2 inputs";
  is $rows[2]->result, 1, "or3 row 2 result";
  ok !$rows[2]->covered, "or3 row 2 not covered";
}

# and_2: $a && constant (right is constant, only 2 paths: l, !l)
sub test_single_and2 () {
  my @conditions = (mock_condition(
    "Condition_and_2",
    [ 1, 0 ],
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
    "Condition_or_2",
    [ 1, 1 ],
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
    [ 0, 1, 1, 0 ],
    { type => "xor_4", left => '$a', op => "xor", right => '$b' },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "xor_4 produces one table";

  my @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $tables[0]->rows;
  is @rows, 4, "xor_4 has four rows";

  # 0,0 -> 0, not covered
  is_deeply $rows[0]->inputs, [ 0, 0 ], "xor row 0 inputs";
  is $rows[0]->result, 0, "xor row 0 result";
  ok !$rows[0]->covered, "xor row 0 not covered";

  # 0,1 -> 1, covered
  is_deeply $rows[1]->inputs, [ 0, 1 ], "xor row 1 inputs";
  is $rows[1]->result, 1, "xor row 1 result";
  ok $rows[1]->covered, "xor row 1 covered";

  # 1,0 -> 1, covered
  is_deeply $rows[2]->inputs, [ 1, 0 ], "xor row 2 inputs";
  is $rows[2]->result, 1, "xor row 2 result";
  ok $rows[2]->covered, "xor row 2 covered";

  # 1,1 -> 0, not covered
  is_deeply $rows[3]->inputs, [ 1, 1 ], "xor row 3 inputs";
  is $rows[3]->result, 0, "xor row 3 result";
  ok !$rows[3]->covered, "xor row 3 not covered";
}

# Composite: $a || $b && $c
# Two conditions on the same line:
#   and_3: left=$b, op=&&, right=$c  (expr = "$b && $c")
#   or_3:  left=$a, op=||, right="$b && $c"
# The or_3's right operand matches the and_3's expression,
# so they form a tree: $a || ($b && $c)
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
      [ 1, 0, 1 ],
      { type => "and_3", left => '$b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_or_3",
      [ 1, 1, 1 ],
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
  is_deeply $rows[0]->inputs, [ 0, 0, "X" ], "comp row 0 inputs";
  is $rows[0]->result, 0, "comp row 0 result";
  ok $rows[0]->covered, "comp row 0 covered";

  # A=0 B=1 C=0 -> 0, NOT covered (and l&&!r not hit)
  is_deeply $rows[1]->inputs, [ 0, 1, 0 ], "comp row 1 inputs";
  is $rows[1]->result, 0, "comp row 1 result";
  ok !$rows[1]->covered, "comp row 1 not covered";

  # A=0 B=1 C=1 -> 1, covered (or !l&&r hit, and l&&r hit)
  is_deeply $rows[2]->inputs, [ 0, 1, 1 ], "comp row 2 inputs";
  is $rows[2]->result, 1, "comp row 2 result";
  ok $rows[2]->covered, "comp row 2 covered";

  # A=1 B=X C=X -> 1, covered (or l hit)
  is_deeply $rows[3]->inputs, [ 1, "X", "X" ], "comp row 3 inputs";
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
      [ 1, 1, 1 ],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_and_3",
      [ 1, 0, 1 ],
      { type => "and_3", left => '$a && $b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_and_3",
      [ 1, 1, 0 ], {
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
  is_deeply $rows[0]->inputs, [ 0, "X", "X", "X" ], "deep row 0";
  ok $rows[0]->covered, "deep row 0 covered";

  # A=1 B=0: first and l&&!r hit -> covered
  is_deeply $rows[1]->inputs, [ 1, 0, "X", "X" ], "deep row 1";
  ok $rows[1]->covered, "deep row 1 covered";

  # A=1 B=1 C=0: second and l&&!r NOT hit -> not covered
  is_deeply $rows[2]->inputs, [ 1, 1, 0, "X" ], "deep row 2";
  ok !$rows[2]->covered, "deep row 2 not covered";

  # A=1 B=1 C=1 D=0: third and l&&!r hit -> covered
  is_deeply $rows[3]->inputs, [ 1, 1, 1, 0 ], "deep row 3";
  ok $rows[3]->covered, "deep row 3 covered";

  # A=1 B=1 C=1 D=1: third and l&&r NOT hit -> not covered
  is_deeply $rows[4]->inputs, [ 1, 1, 1, 1 ], "deep row 4";
  ok !$rows[4]->covered, "deep row 4 not covered";
}

# Multiple independent conditions on one line (e.g. two statements)
sub test_independent_conditions () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [ 1, 0, 1 ],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_or_3",
      [ 1, 1, 0 ],
      { type => "or_3", left => '$x', op => "||", right => '$y' },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 2, "independent conditions produce two tables";

  my @exprs = sort map { $_->expr } @tables;
  is_deeply \@exprs, [ '$a && $b', '$x || $y' ], "both expressions present";
}

# > 16 conditions returns empty list
sub test_too_many_conditions () {
  my @conditions = map {
    mock_condition(
      "Condition_and_3",
      [ 1, 1, 1 ],
      { type => "and_3", left => "\$a$_", op => "&&", right => "\$b$_" },
    )
  } 1 .. 17;

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 0, "> 16 conditions returns empty";
}

# undef in hit counts (Devel::Cover can produce these)
sub test_undef_hits () {
  my @conditions = (mock_condition(
    "Condition_and_3",
    [ undef, 0, 1 ],
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
    "Condition",
    [ 1, 0 ],
    { type => "unknown", left => '$a', op => "??", right => '$b' },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "unknown type produces a table";

  my @rows = $tables[0]->rows;
  is @rows, 0, "unknown type table has no rows";
}

# Single-input condition with sub-expression: or_2 where left is
# a sub-expression with an uncovered path.
# This exercises the $row->covered && $le->[1] branch where
# $row->covered is true but $le->[1] is false.
sub test_single_input_with_subexpr () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [ 1, 0, 1 ],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_or_2",
      [ 1, 1 ],
      { type => "or_2", left => '$a && $b', op => "||", right => "0" },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "or_2 with sub-expr produces one table";

  my @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $tables[0]->rows;
  is @rows, 3, "or_2 with sub-expr has three rows";

  # A=0 B=X -> or_2 left=0 (result 0), and_3 !l path covered
  # or_2 covered=1, and_3 covered=1 -> covered
  is_deeply $rows[0]->inputs, [ 0, "X" ], "subexpr row 0 inputs";
  ok $rows[0]->covered, "subexpr row 0 covered";

  # A=1 B=0 -> or_2 left=0 (result 0), and_3 l&&!r NOT covered
  # or_2 covered=1, and_3 covered=0 -> NOT covered
  is_deeply $rows[1]->inputs, [ 1, 0 ], "subexpr row 1 inputs";
  ok !$rows[1]->covered, "subexpr row 1 not covered (sub-expr uncovered)";

  # A=1 B=1 -> or_2 left=1 (result 1), and_3 l&&r covered
  # or_2 covered=1, and_3 covered=1 -> covered
  is_deeply $rows[2]->inputs, [ 1, 1 ], "subexpr row 2 inputs";
  ok $rows[2]->covered, "subexpr row 2 covered";
}

# Labels: single and_3 has two leaf labels
sub test_labels_simple () {
  my @conditions = (mock_condition(
    "Condition_and_3",
    [ 1, 0, 1 ],
    { type => "and_3", left => '$a', op => "&&", right => '$b' },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is_deeply [ $tables[0]->labels ], [ '$a', '$b' ],
    "labels: simple and_3 has two leaf labels";
}

# Labels: composite $a || ($b && $c) has three leaf labels
sub test_labels_composite () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [ 1, 0, 1 ],
      { type => "and_3", left => '$b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_or_3",
      [ 1, 1, 1 ],
      { type => "or_3", left => '$a', op => "||", right => '$b && $c' },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is_deeply [ $tables[0]->labels ], [ '$a', '$b', '$c' ],
    "labels: composite has three leaf labels";
}

# Labels: deep chain $a && $b && $c && $d
sub test_labels_deep_chain () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [ 1, 1, 1 ],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_and_3",
      [ 1, 0, 1 ],
      { type => "and_3", left => '$a && $b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_and_3",
      [ 1, 1, 0 ], {
        type  => "and_3",
        left  => '$a && $b && $c',
        op    => "&&",
        right => '$d',
      },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is_deeply [ $tables[0]->labels ], [ '$a', '$b', '$c', '$d' ],
    "labels: deep chain has four leaf labels";
}

# Labels: boolean (single-input) condition
sub test_labels_boolean () {
  my @conditions = (mock_condition(
    "Condition_and_2",
    [ 1, 0 ],
    { type => "and_2", left => '$a', op => "&&", right => "1" },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is_deeply [ $tables[0]->labels ], ['$a'], "labels: boolean has one label";
}

# Labels: or_2 with sub-expression on left
sub test_labels_boolean_with_subexpr () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [ 1, 0, 1 ],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_or_2",
      [ 1, 1 ],
      { type => "or_2", left => '$a && $b', op => "||", right => "0" },
    ),
  );

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is_deeply [ $tables[0]->labels ], [ '$a', '$b' ],
    "labels: boolean with sub-expr expands to leaf labels";
}

# short_expr: operator structure with letters
sub test_short_expr_simple () {
  my @conditions = (mock_condition(
    "Condition_and_3",
    [ 1, 0, 1 ],
    { type => "and_3", left => '$a', op => "&&", right => '$b' },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is $tables[0]->short_expr, "A && B", "short_expr: simple and_3";
}

sub test_short_expr_composite () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [ 1, 0, 1 ],
      { type => "and_3", left => '$b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_or_3",
      [ 1, 1, 1 ],
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
      [ 1, 1, 1 ],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    mock_condition(
      "Condition_and_3",
      [ 1, 0, 1 ],
      { type => "and_3", left => '$a && $b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_and_3",
      [ 1, 1, 0 ], {
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
    "Condition_or_2",
    [ 1, 1 ],
    { type => "or_2", left => '$a', op => "||", right => "0" },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is $tables[0]->short_expr, "A", "short_expr: boolean";
}

# Nested mixed operators: @a == 1 || (@a == 2 && $b && $c)
# produces three conditions that should merge into one 4-variable
# table. The metadata left/right fields must match _expr() output
# of child conditions (no spurious parentheses).
sub test_nested_mixed_operators () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [ 1, 1, 1 ],
      { type => "and_3", left => '@a == 2', op => "and", right => '$b' },
    ),
    mock_condition(
      "Condition_and_3",
      [ 1, 0, 1 ], {
        type  => "and_3",
        left  => '@a == 2 and $b',
        op    => "and",
        right => '$c',
      },
    ),
    mock_condition(
      "Condition_or_3",
      [ 0, 0, 1 ], {
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
  is_deeply [ $t->labels ], [ '@a == 1', '@a == 2', '$b', '$c' ],
    "nested: labels resolve through tree";

  my @rows = $t->rows;
  is @rows, 5, "nested: merged table has five rows";
}

# Extra addr fields in metadata should be ignored when not used for
# linking.  This is a baseline test to confirm no regression.
sub test_addr_fields_passthrough () {
  my @conditions = (mock_condition(
    "Condition_and_3",
    [ 1, 0, 1 ],
    {
      type      => "and_3",
      left      => '$a',
      op        => "&&",
      right     => '$b',
      addr      => 100,
      left_addr => 200,
      right_addr => 300,
    },
  ));

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  is @tables, 1, "addr passthrough: one table";
  is $tables[0]->expr, '$a && $b', "addr passthrough: expr unchanged";

  my @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $tables[0]->rows;
  is @rows, 3, "addr passthrough: three rows";
  ok $rows[0]->covered,  "addr passthrough: row 0 covered";
  ok !$rows[1]->covered, "addr passthrough: row 1 not covered";
  ok $rows[2]->covered,  "addr passthrough: row 2 covered";
}

# Addr-based linking: parent's right string is deliberately wrong but
# right_addr matches child's addr.  Tree linking should still work.
sub test_addr_linking () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [ 1, 0, 1 ],
      {
        type => "and_3", left => '$b', op => "&&", right => '$c',
        addr => 42,
      },
    ),
    mock_condition(
      "Condition_or_3",
      [ 1, 1, 0 ],
      {
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
  is_deeply [ $tables[0]->labels ], [ '$a', '$b', '$c' ],
    "addr linking: labels from child condition";
}

# Deep chain with addr linking: string left values are wrong but
# left_addr values chain correctly.
sub test_addr_linking_deep_chain () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [ 1, 1, 1 ],
      {
        type => "and_3", left => '$a', op => "&&", right => '$b',
        addr => 10,
      },
    ),
    mock_condition(
      "Condition_and_3",
      [ 1, 0, 1 ],
      {
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
      [ 1, 1, 0 ],
      {
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
  is_deeply [ $tables[0]->labels ], [ '$a', '$b', '$c', '$d' ],
    "addr deep chain: four leaf labels";
  is $tables[0]->short_expr, "A && B && C && D",
    "addr deep chain: short_expr";

  my @rows = $tables[0]->rows;
  is @rows, 5, "addr deep chain: five rows";
}

# Fallback to string matching when addr fields are absent.
sub test_addr_fallback_to_string () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [ 1, 0, 1 ],
      { type => "and_3", left => '$b', op => "&&", right => '$c' },
    ),
    mock_condition(
      "Condition_or_3",
      [ 1, 1, 0 ],
      {
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
  is_deeply [ $tables[0]->labels ], [ '$a', '$b', '$c' ],
    "addr fallback: labels from string-matched child";
}

# Addr takes priority over conflicting string match.
sub test_addr_overrides_string () {
  my @conditions = (
    # X: addr 10, _expr = "$b && $c"
    mock_condition(
      "Condition_and_3",
      [ 1, 0, 1 ],
      {
        type => "and_3", left => '$b', op => "&&", right => '$c',
        addr => 10,
      },
    ),
    # Y: addr 20, _expr = "$d && $e" (matches parent's right by string)
    mock_condition(
      "Condition_and_3",
      [ 1, 1, 0 ],
      {
        type => "and_3", left => '$d', op => "&&", right => '$e',
        addr => 20,
      },
    ),
    # Parent: right string matches Y, but right_addr points to X
    mock_condition(
      "Condition_or_3",
      [ 0, 1, 1 ],
      {
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
  is_deeply [ $root->labels ], [ '$a', '$b', '$c' ],
    "addr priority: links to addr match, not string match";
}

# Negated sub-expression: $a || not($b && $c)
# The compiler can transform !X && !Y into not(X || Y) via DeMorgan.
# The right operand of the outer or is negated, so when the outer or
# sees right=1, it means not(and_result)=1, i.e. and_result=0.
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
sub test_negated_subexpr () {
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [ 1, 0, 1 ],
      {
        type => "and_3", left => '$b', op => "&&", right => '$c',
        addr => 42,
      },
    ),
    mock_condition(
      "Condition_or_3",
      [ 1, 1, 1 ],
      {
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
  is $t->short_expr, 'A || not(B && C)',
    "negated: heading shows not(...)";

  my @rows = sort { "@{$a->inputs}" cmp "@{$b->inputs}" } $t->rows;
  is @rows, 4, "negated: four rows";

  # A=0 B=0 C=X -> 1 (not(and=0)=1, or: left=0,right=1 -> 1)
  is_deeply $rows[0]->inputs, [ 0, 0, "X" ], "neg row 0 inputs";
  is $rows[0]->result, 1, "neg row 0 result";
  ok $rows[0]->covered, "neg row 0 covered";

  # A=0 B=1 C=0 -> 1 (not(and=0)=1, or: left=0,right=1 -> 1)
  is_deeply $rows[1]->inputs, [ 0, 1, 0 ], "neg row 1 inputs";
  is $rows[1]->result, 1, "neg row 1 result";
  ok !$rows[1]->covered, "neg row 1 not covered (and path l&&!r not hit)";

  # A=0 B=1 C=1 -> 0 (not(and=1)=0, or: left=0,right=0 -> 0)
  is_deeply $rows[2]->inputs, [ 0, 1, 1 ], "neg row 2 inputs";
  is $rows[2]->result, 0, "neg row 2 result";
  ok $rows[2]->covered, "neg row 2 covered";

  # A=1 B=X C=X -> 1 (or: left=1 -> 1)
  is_deeply $rows[3]->inputs, [ 1, "X", "X" ], "neg row 3 inputs";
  is $rows[3]->result, 1, "neg row 3 result";
  ok $rows[3]->covered, "neg row 3 covered";
}

sub main () {
  test_single_and3;
  test_single_or3;
  test_single_and2;
  test_single_or2;
  test_single_xor4;
  test_composite_or_and;
  test_deep_and_chain;
  test_independent_conditions;
  test_too_many_conditions;
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
  test_negated_subexpr;
  done_testing;
}

main;

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

use Test::More import => [qw( done_testing is isnt ok plan subtest )];

use B        ();
use XSLoader ();

# Load just the XS - skip Devel::Cover->import so no DB directory is created.
require Devel::Cover;
XSLoader::load("Devel::Cover");

# Find every op of $name under $root, returned in depth-first encounter order.
sub find_all_ops ($op, $name, $found = []) {
  push @$found, $op if $op->name eq $name;
  return $found unless $op->flags & B::OPf_KIDS();
  return $found if $op->name eq "custom";
  for (my $kid = $op->first; $$kid; $kid = $kid->sibling) {
    find_all_ops($kid, $name, $found);
  }
  $found
}

# Return the user-code logop matching $name.  Signatures on Perl < 5.28 expand
# to extra `or` ops at the top of the optree for argument-count checks, so
# depth-first first-match returns the wrong op.  The user's logop is always
# emitted last, after the signature setup, so taking the final entry in the
# depth-first list yields the user-code op.
sub find_user_op ($root, $name) {
  my $found = find_all_ops($root, $name);
  $found->[-1];
}

sub meta_for_sub ($code, $opname) {
  my $cv = B::svref_2object($code);
  my $op = find_user_op($cv->ROOT, $opname) or die "no $opname op found";
  Devel::Cover::decision_meta($$op, $cv);
}

subtest "two-leaf and: simple root" => sub {
  my $sub  = sub ($x, $y) { my $r = $x && $y; $r };
  my $meta = meta_for_sub($sub, "and");

  ok $meta, "decision meta returned";
  is $meta->{is_root},        1, "is_root";
  is $meta->{width},          2, "width";
  is $meta->{leaf_col_left},  0, "left leaf column";
  is $meta->{leaf_col_right}, 1, "right leaf column";
};

subtest 'multiconcat right with truthy literal: $p && "foo $q"' => sub {
  plan skip_all => "OP_MULTICONCAT requires Perl >= 5.28" if $] < 5.028;
  my $sub  = sub ($p, $q) { my $r = $p && "foo $q"; $r };
  my $meta = meta_for_sub($sub, "and");

  ok $meta, "decision meta returned";
  is $meta->{is_root},         1, "is_root";
  is $meta->{width},           1, "width is 1 (right is const-truthy)";
  is $meta->{leaf_col_left},   0, "left leaf column 0";
  is $meta->{leaf_col_right}, -1, "right is const (multiconcat truthy)";
};

subtest 'multiconcat right with falsy literal: $p && "0$q"' => sub {
  my $sub  = sub ($p, $q) { my $r = $p && "0$q"; $r };
  my $meta = meta_for_sub($sub, "and");

  ok $meta, "decision meta returned";
  is $meta->{is_root},           1, "is_root";
  is $meta->{width},             2, 'width is 2 (literal "0" is falsy)';
  is $meta->{leaf_col_left},     0, "left leaf column 0";
  isnt $meta->{leaf_col_right}, -1, "right is not const (falsy literal)";
};

subtest 'nested mixed-precedence: ($w && $x) || ($y && $z)' => sub {
  my $sub = sub ($w, $x, $y, $z) { my $r = ($w && $x) || ($y && $z); $r };
  my $cv  = B::svref_2object($sub);

  my $or      = find_user_op($cv->ROOT, "or") or die "no or op";
  my $and_ops = find_all_ops($cv->ROOT, "and");
  is @$and_ops, 2, "two AND ops in optree";

  my $or_meta    = Devel::Cover::decision_meta($$or,               $cv);
  my $left_meta  = Devel::Cover::decision_meta(${ $and_ops->[0] }, $cv);
  my $right_meta = Devel::Cover::decision_meta(${ $and_ops->[1] }, $cv);

  ok $or_meta,    "or meta returned";
  ok $left_meta,  "left and meta returned";
  ok $right_meta, "right and meta returned";

  is $or_meta->{is_root},         1,   "outer || is root";
  is $or_meta->{width},           4,   "outer || width is 4";
  is $or_meta->{leaf_col_left},  -1,   "outer || left is logop";
  is $or_meta->{leaf_col_right}, -1,   "outer || right is logop";
  is $or_meta->{root_addr},      $$or, "outer || root_addr points to itself";

  is $left_meta->{is_root},        0,    "inner-left && not root";
  is $left_meta->{width},          4,    "inner-left && width is 4";
  is $left_meta->{leaf_col_left},  0,    "inner-left && left col 0";
  is $left_meta->{leaf_col_right}, 1,    "inner-left && right col 1";
  is $left_meta->{root_addr},      $$or, "inner-left && root_addr is outer ||";

  is $right_meta->{is_root},        0, "inner-right && not root";
  is $right_meta->{width},          4, "inner-right && width is 4";
  is $right_meta->{leaf_col_left},  2, "inner-right && left col 2";
  is $right_meta->{leaf_col_right}, 3, "inner-right && right col 3";
  is $right_meta->{root_addr}, $$or,   "inner-right && root_addr is outer ||";
};

# Signatures on Perl < 5.28 expand to extra `or` ops in the prologue for
# argument-count handling.  These should be analysed as their own width-2 roots,
# isolated from the user's decision: pairwise root-finding must not mistake a
# signature `or` for the parent of a user logop, and the user's `||` must remain
# a width-4 root.
subtest "signature-generated logops are excluded" => sub {
  my $sub = sub ($w, $x, $y, $z) { my $r = ($w && $x) || ($y && $z); $r };
  my $cv  = B::svref_2object($sub);

  my $or_ops  = find_all_ops($cv->ROOT, "or");
  my $and_ops = find_all_ops($cv->ROOT, "and");

  my $user_or = $or_ops->[-1];
  ok @$or_ops >= 1, "at least one or op present";
  is @$and_ops, 2, "two and ops (all user-code on every Perl)";

  # A signature argument-count check is a void or with a die on its right,
  # which is the branch form, so it gets no decision meta at all.
  for my $i (0 .. $#$or_ops - 1) {
    my $m = Devel::Cover::decision_meta(${ $or_ops->[$i] }, $cv);
    is $m, undef, "signature or [$i]: branch-style, no decision meta";
  }

  my $um = Devel::Cover::decision_meta($$user_or, $cv);
  is $um->{width},     4,         "user || width unaffected by signature ops";
  is $um->{is_root},   1,         "user || still root";
  is $um->{root_addr}, $$user_or, "user || root_addr points to itself";

  for my $and (@$and_ops) {
    my $am = Devel::Cover::decision_meta($$and, $cv);
    is $am->{root_addr}, $$user_or,
      "inner && root_addr is user ||, not a signature or";
  }
};

done_testing;

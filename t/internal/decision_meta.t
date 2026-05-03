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

use Test::More import => [qw( done_testing is isnt ok subtest )];

use B           ();
use XSLoader   ();

# Load just the XS - skip Devel::Cover->import so no DB directory is created.
require Devel::Cover;
XSLoader::load("Devel::Cover");

# Recursively descend an op tree and return the first op whose name matches.
sub find_op ($op, $name) {
  return $op if $op->name eq $name;
  return                              unless $op->flags & B::OPf_KIDS();
  return                              if $op->name eq "custom";
  for (my $kid = $op->first; $$kid; $kid = $kid->sibling) {
    my $found = find_op($kid, $name);
    return $found if $found;
  }
  return;
}

sub meta_for_sub ($code, $opname) {
  my $cv  = B::svref_2object($code);
  my $op  = find_op($cv->ROOT, $opname) or die "no $opname op found";
  Devel::Cover::_decision_meta($$op, $cv);
}

# Find every op of $name under $root, returned in depth-first encounter order.
sub find_all_ops ($op, $name, $found = []) {
  push @$found, $op if $op->name eq $name;
  return $found                            unless $op->flags & B::OPf_KIDS();
  return $found                            if $op->name eq "custom";
  for (my $kid = $op->first; $$kid; $kid = $kid->sibling) {
    find_all_ops($kid, $name, $found);
  }
  return $found;
}

subtest "two-leaf and: simple root" => sub {
  my $sub  = sub ($a, $b) { my $r = $a && $b; $r };
  my $meta = meta_for_sub($sub, "and");

  ok $meta, "decision meta returned";
  is $meta->{is_root},        1, "is_root";
  is $meta->{width},          2, "width";
  is $meta->{leaf_col_left},  0, "left leaf column";
  is $meta->{leaf_col_right}, 1, "right leaf column";
};

subtest 'multiconcat right with truthy literal: $p && "foo $q"' => sub {
  my $sub  = sub ($p, $q) { my $r = $p && "foo $q"; $r };
  my $meta = meta_for_sub($sub, "and");

  ok $meta, "decision meta returned";
  is $meta->{is_root},        1,  "is_root";
  is $meta->{width},          1,  "width is 1 (right is const-truthy)";
  is $meta->{leaf_col_left},  0,  "left leaf column 0";
  is $meta->{leaf_col_right}, -1, "right is const (multiconcat truthy)";
};

subtest 'multiconcat right with falsy literal: $p && "0$q"' => sub {
  my $sub  = sub ($p, $q) { my $r = $p && "0$q"; $r };
  my $meta = meta_for_sub($sub, "and");

  ok $meta, "decision meta returned";
  is $meta->{is_root},       1, "is_root";
  is $meta->{width},         2, qq(width is 2 (literal "0" is falsy));
  is $meta->{leaf_col_left}, 0, "left leaf column 0";
  isnt $meta->{leaf_col_right}, -1, "right is not const (falsy literal)";
};

subtest 'nested mixed-precedence: ($a && $b) || ($c && $d)' => sub {
  my $sub = sub ($a, $b, $c, $d) { my $r = ($a && $b) || ($c && $d); $r };
  my $cv  = B::svref_2object($sub);

  my $or  = find_op($cv->ROOT, "or") or die "no or op";
  my $and_ops = find_all_ops($cv->ROOT, "and");
  is scalar @$and_ops, 2, "two AND ops in optree";

  my $or_meta    = Devel::Cover::_decision_meta($$or, $cv);
  my $left_meta  = Devel::Cover::_decision_meta(${ $and_ops->[0] }, $cv);
  my $right_meta = Devel::Cover::_decision_meta(${ $and_ops->[1] }, $cv);

  ok $or_meta,    "or meta returned";
  ok $left_meta,  "left and meta returned";
  ok $right_meta, "right and meta returned";

  is $or_meta->{is_root},        1,   "outer || is root";
  is $or_meta->{width},          4,   "outer || width is 4";
  is $or_meta->{leaf_col_left},  -1,  "outer || left is logop";
  is $or_meta->{leaf_col_right}, -1,  "outer || right is logop";
  is $or_meta->{root_addr}, $$or,     "outer || root_addr points to itself";

  is $left_meta->{is_root},        0,    "inner-left && not root";
  is $left_meta->{width},          4,    "inner-left && width is 4";
  is $left_meta->{leaf_col_left},  0,    "inner-left && left col 0";
  is $left_meta->{leaf_col_right}, 1,    "inner-left && right col 1";
  is $left_meta->{root_addr}, $$or,      "inner-left && root_addr is outer ||";

  is $right_meta->{is_root},        0,    "inner-right && not root";
  is $right_meta->{width},          4,    "inner-right && width is 4";
  is $right_meta->{leaf_col_left},  2,    "inner-right && left col 2";
  is $right_meta->{leaf_col_right}, 3,    "inner-right && right col 3";
  is $right_meta->{root_addr}, $$or,      "inner-right && root_addr is outer ||";
};

done_testing;

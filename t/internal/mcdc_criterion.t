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

use Test::More import => [qw( done_testing is is_deeply )];

use Devel::Cover::Mcdc ();

# An Mcdc instance is a blessed arrayref [coverage, info] matching
# Branch.pm's shape.  coverage is per-column 1/0 (satisfied / missing),
# one entry per atomic column in the decision.
sub mcdc ($coverage, $text = '$a && $b') {
  bless [$coverage, { text => $text }], "Devel::Cover::Mcdc"
}

sub test_total_counts_columns () {
  my $m = mcdc([1, 1, 0]);
  is $m->total, 3, "total counts every column";
}

sub test_covered_counts_satisfied_columns () {
  my $m = mcdc([1, 1, 0]);
  is $m->covered, 2, "covered counts satisfied columns";
}

sub test_covered_zero () {
  my $m = mcdc([0, 0, 0]);
  is $m->covered, 0, "covered zero when nothing satisfied";
}

sub test_percentage_full () {
  my $m = mcdc([1, 1]);
  is $m->percentage, "100", "100% when every column satisfied";
}

sub test_percentage_zero () {
  my $m = mcdc([0, 0]);
  is $m->percentage, "  0", "0% when nothing satisfied";
}

# 2/3 = 66.67 -> sprintf "%3d" truncates to 66, matching Branch.pm's
# rounding.
sub test_percentage_truncates () {
  my $m = mcdc([1, 1, 0]);
  is $m->percentage, " 66", "percentage truncates toward zero";
}

sub test_criterion_name () {
  my $m = mcdc([1]);
  is $m->criterion, "mcdc", "criterion name";
}

sub test_text () {
  my $m = mcdc([1, 1], '$x || $y');
  is $m->text, '$x || $y', "text returns the decision expression";
}

sub test_values () {
  my $m = mcdc([1, 0, 1]);
  is_deeply [$m->values], [1, 0, 1], "values returns the per-column list";
}

sub main () {
  test_total_counts_columns;
  test_covered_counts_satisfied_columns;
  test_covered_zero;
  test_percentage_full;
  test_percentage_zero;
  test_percentage_truncates;
  test_criterion_name;
  test_text;
  test_values;
  done_testing;
}

main;

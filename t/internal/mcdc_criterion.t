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

use Devel::Cover::Mcdc ();  ## no perlimports

# An Mcdc instance is a blessed arrayref [coverage, info, uncoverable] like
# Branch.pm: per-column 1/0 coverage and a parallel uncoverable flag.
sub mcdc (
  $coverage, $text = '$a && $b', $uncoverable = undef, $labels = undef
) {
  bless [$coverage, { text => $text, labels => $labels }, $uncoverable],
    "Devel::Cover::Mcdc"
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
  is $m->percentage, 100, "100% when every column satisfied";
}

sub test_percentage_zero () {
  my $m = mcdc([0, 0]);
  is $m->percentage, 0, "0% when nothing satisfied";
}

# 2/3 = 66.67 -> int() truncates to 66, matching Branch.pm's rounding.
sub test_percentage_truncates () {
  my $m = mcdc([1, 1, 0]);
  is $m->percentage, 66, "percentage truncates toward zero";
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

sub test_uncoverable_per_column () {
  my $m = mcdc([0, 0], '$a // $b', [0, 1]);
  is $m->uncoverable(0), 0, "uncoverable(i) false for unmarked column";
  is $m->uncoverable(1), 1, "uncoverable(i) true for marked column";
  is $m->uncoverable,    1, "uncoverable() counts marked columns";
}

sub test_uncoverable_absent () {
  my $m = mcdc([1, 0]);
  is $m->uncoverable, 0, "uncoverable() zero when no markers present";
}

sub test_error_excuses_marked_missing () {
  # Column 0 missing and unmarked -> error; column 1 missing but marked
  # uncoverable -> excused.
  my $m = mcdc([0, 0], '$a // $b', [0, 1]);
  is $m->error, 1, "only the unmarked missing column counts as an error";
}

sub test_error_flags_covered_but_marked () {
  # A column that is covered yet marked uncoverable is a mismatch.
  my $m = mcdc([1, 1], '$a // $b', [0, 1]);
  is $m->error, 1, "a covered column marked uncoverable is an error";
}

sub test_fully_marked_decision_has_no_error () {
  my $m = mcdc([0, 0], '$a // $b', [1, 1]);
  is $m->error, 0, "a wholly uncoverable decision reports no error";
}

sub test_missing_excludes_marked () {
  my $m = mcdc([0, 0], '$a // $b', [0, 1], ['$a', '$b']);
  is_deeply $m->missing, ['$a'], "missing omits columns marked uncoverable";
}

sub test_unanalysed_flag () {
  my $m = bless [[0, 0], { text => '$a && $b', unanalysed => 1 }],
    "Devel::Cover::Mcdc";
  is $m->unanalysed, 1, "unanalysed true when flagged";
}

sub test_unanalysed_default () {
  my $m = mcdc([1, 0]);
  is $m->unanalysed, 0, "unanalysed false when not flagged";
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
  test_uncoverable_per_column;
  test_uncoverable_absent;
  test_error_excuses_marked_missing;
  test_error_flags_covered_but_marked;
  test_fully_marked_decision_has_no_error;
  test_missing_excludes_marked;
  test_unanalysed_flag;
  test_unanalysed_default;
  done_testing;
}

main;

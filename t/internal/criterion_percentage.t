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

use Devel::Cover::Branch         ();  ## no perlimports
use Devel::Cover::Condition_or_3 ();  ## no perlimports
use Devel::Cover::Mcdc           ();  ## no perlimports
use Devel::Cover::Pod            ();  ## no perlimports
use Devel::Cover::Statement      ();  ## no perlimports
use Devel::Cover::Subroutine     ();  ## no perlimports

sub statement ($covered, $uncoverable = undef) {
  bless [$covered, $uncoverable], "Devel::Cover::Statement"
}

sub subroutine ($covered, $uncoverable = undef) {
  bless [$covered, "main::foo", $uncoverable], "Devel::Cover::Subroutine"
}

sub pod ($covered, $uncoverable = undef) {
  bless [$covered, undef, $uncoverable], "Devel::Cover::Pod"
}

sub branch ($covered, $uncoverable = undef) {
  bless [$covered, { text => '$a' }, $uncoverable], "Devel::Cover::Branch"
}

sub condition ($covered, $uncoverable = undef) {
  bless [$covered, { left => '$a', op => "or", right => '$b' }, $uncoverable],
    "Devel::Cover::Condition_or_3"
}

sub mcdc ($covered, $uncoverable = undef) {
  bless [$covered, { text => '$a && $b' }, $uncoverable], "Devel::Cover::Mcdc"
}

sub test_single_construct_states () {
  my @makers = ([\&statement, "statement"], [\&subroutine, "subroutine"],
    [\&pod, "pod"]);
  for my $maker (@makers) {
    my ($make, $name) = @$maker;
    is $make->(1)->percentage,    100, "covered $name is 100%";
    is $make->(0)->percentage,    0,   "uncovered $name is 0%";
    is $make->(0, 1)->percentage, 100, "excused $name is 100%";
    is $make->(1, 1)->percentage, 0,   "covered but marked $name is 0%";
  }
}

sub test_vector_states () {
  my @makers
    = ([\&branch, "branch"], [\&condition, "condition"], [\&mcdc, "mcdc"]);
  for my $maker (@makers) {
    my ($make, $name) = @$maker;
    is $make->([1, 1])->percentage, 100, "fully covered $name is 100%";
    is $make->([1, 0])->percentage, 50,  "half covered $name is 50%";
    is $make->([0, 0])->percentage, 0,   "uncovered $name is 0%";
    is $make->([0, 0], [0, 1])->percentage, 50,
      "excused path counts as success for $name";
    is $make->([0, 0], [1, 1])->percentage, 100, "fully excused $name is 100%";
    is $make->([1, 1], [0, 1])->percentage, 50,
      "covered but marked path counts as error for $name";
    is $make->([0, 0, 0], [0, 0, 1])->percentage, 33,
      "$name percentage truncates toward zero";
  }
}

sub test_ignore_covered_err () {
  no warnings "once";
  local $Devel::Cover::Ignore_covered_err = 1;
  is statement(1, 1)->percentage, 100,
    "covered but marked statement is 100% under ignore_covered_err";
  is branch([1, 1], [0, 1])->percentage, 100,
    "covered but marked branch is 100% under ignore_covered_err";
  is branch([0, 0], [0, 1])->percentage, 50,
    "excused branch still credited under ignore_covered_err";
}

sub test_pod_summary_aggregates_uncoverable () {
  local $INC{"Pod/Coverage.pm"} = $INC{"Pod/Coverage.pm"} // "mocked";
  my $db = { summary => {} };
  pod(0, 1)->calculate_summary($db, "file.pl");
  my $counts = { total => 1, uncoverable => 1 };
  is_deeply $db->{summary}, {
      "file.pl" => { pod => $counts, total => $counts },
      Total     => { pod => $counts, total => $counts },
    },
    "pod summary aggregates the uncoverable count";
}

sub test_pod_summary_covered_but_marked () {
  local $INC{"Pod/Coverage.pm"} = $INC{"Pod/Coverage.pm"} // "mocked";
  my $db = { summary => {} };
  pod(1, 1)->calculate_summary($db, "file.pl");
  my $counts = { total => 1, uncoverable => 1, covered => 1, error => 1 };
  is_deeply $db->{summary}, {
      "file.pl" => { pod => $counts, total => $counts },
      Total     => { pod => $counts, total => $counts },
    },
    "pod summary flags a covered but marked subroutine as an error";
}

sub main () {
  test_single_construct_states;
  test_vector_states;
  test_ignore_covered_err;
  test_pod_summary_aggregates_uncoverable;
  test_pod_summary_covered_but_marked;
  done_testing;
}

main

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

use Devel::Cover::Criterion ();
use Devel::Cover::DB        ();

my %Expected = (
  statement => {
    shortname         => "stmt",
    display_name      => "Statement",
    display_mode      => "count",
    detail_criterion  => undef,
    has_detail_page   => "",
    measures_coverage => 1,
    sign_letter       => "S",
  },
  branch => {
    shortname         => "bran",
    display_name      => "Branch",
    display_mode      => "percentage",
    detail_criterion  => "branch",
    has_detail_page   => 1,
    measures_coverage => 1,
    sign_letter       => "B",
  },
  condition => {
    shortname         => "cond",
    display_name      => "Condition",
    display_mode      => "percentage",
    detail_criterion  => "condition",
    has_detail_page   => 1,
    measures_coverage => 1,
    sign_letter       => "C",
  },
  mcdc => {
    shortname         => "mcdc",
    display_name      => "MC/DC",
    display_mode      => "percentage",
    detail_criterion  => "mcdc",
    has_detail_page   => 1,
    measures_coverage => 1,
    sign_letter       => "M",
  },
  subroutine => {
    shortname         => "sub",
    display_name      => "Subroutine",
    display_mode      => "count",
    detail_criterion  => "subroutine",
    has_detail_page   => 1,
    measures_coverage => 1,
    sign_letter       => "R",
  },
  pod => {
    shortname         => "pod",
    display_name      => "Pod",
    display_mode      => "count",
    detail_criterion  => "subroutine",
    has_detail_page   => "",
    measures_coverage => 1,
    sign_letter       => "P",
  },
  time => {
    shortname         => "time",
    display_name      => "Time",
    display_mode      => "count",
    detail_criterion  => undef,
    has_detail_page   => "",
    measures_coverage => 0,
    sign_letter       => undef,
  },
);

sub test_canonical_lists () {
  my @names = Devel::Cover::Criterion->criterion_names;
  is_deeply \@names,
    [qw( statement branch condition mcdc subroutine pod time )],
    "canonical criterion names in order";

  is_deeply \@Devel::Cover::DB::Criteria, \@names,
    "DB Criteria list derives from the metadata";
  is_deeply \@Devel::Cover::DB::Criteria_short,
    [qw( stmt bran cond mcdc sub pod time )],
    "DB short list derives from the metadata";
}

sub test_criterion_metadata () {
  for my $name (Devel::Cover::Criterion->criterion_names) {
    my $class = Devel::Cover::Criterion->criterion_class($name);
    is $class->criterion, $name, "$class criterion is $name";
    my $e = $Expected{$name};
    for my $method (sort keys %$e) {
      is $class->$method, $e->{$method}, "$name $method";
    }
  }
}

sub test_derived_lists () {
  is_deeply [Devel::Cover::Criterion->coverage_criteria],
    [qw( statement branch condition mcdc subroutine pod )],
    "coverage_criteria excludes time";

  is_deeply [Devel::Cover::Criterion->editor_criteria],
    [qw( statement branch condition mcdc subroutine pod )],
    "editor_criteria is the canonical order minus time";
}

sub test_condition_subclasses () {
  ok +Devel::Cover::Condition_or_2->measures_coverage,
    "Condition subclasses inherit metadata";
  is +Devel::Cover::Condition_or_2->shortname, "cond",
    "Condition subclasses inherit the shortname";
}

sub main () {
  test_canonical_lists;
  test_criterion_metadata;
  test_derived_lists;
  test_condition_subclasses;
  done_testing;
}

main;

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

use Test::More import => [qw( done_testing is )];

use Devel::Cover::Branch     ();  ## no perlimports
use Devel::Cover::Mcdc       ();  ## no perlimports
use Devel::Cover::Statement  ();  ## no perlimports
use Devel::Cover::Subroutine ();  ## no perlimports

sub statement ($covered, $uncoverable = undef) {
  bless [$covered, $uncoverable], "Devel::Cover::Statement"
}

sub subroutine ($covered, $uncoverable = undef) {
  bless [$covered, "main::foo", $uncoverable], "Devel::Cover::Subroutine"
}

sub branch ($covered, $uncoverable = undef) {
  bless [$covered, { text => '$a' }, $uncoverable], "Devel::Cover::Branch"
}

sub mcdc ($covered, $uncoverable = undef) {
  bless [$covered, { text => '$a && $b' }, $uncoverable], "Devel::Cover::Mcdc"
}

sub test_scalar_states () {
  my @makers = ([\&statement, "statement"], [\&subroutine, "subroutine"]);
  for my $maker (@makers) {
    my ($make, $name) = @$maker;
    is $make->(1)->coverage_state,            "covered",   "covered $name";
    is $make->(0)->coverage_state,            "uncovered", "uncovered $name";
    is $make->(0, "default")->coverage_state, "excused",   "excused $name";
    is $make->(1, "default")->coverage_state, "stale",
      "covered but marked $name is stale";
  }
}

sub test_indexed_states () {
  my @makers = ([\&branch, "branch"], [\&mcdc, "mcdc"]);
  for my $maker (@makers) {
    my ($make, $name) = @$maker;
    my $o = $make->([1, 0, 0, 1], [0, 0, "default", "default"]);
    is $o->coverage_state(0), "covered",   "covered $name path";
    is $o->coverage_state(1), "uncovered", "uncovered $name path";
    is $o->coverage_state(2), "excused",   "excused $name path";
    is $o->coverage_state(3), "stale",     "covered but marked $name path";
  }
}

sub test_ignore_covered_err () {
  no warnings "once";
  local $Devel::Cover::Ignore_covered_err = 1;
  is statement(1, "default")->coverage_state, "covered",
    "stale statement forgiven under -ignore_covered_err";
  is statement(0, "default")->coverage_state, "excused",
    "excused statement stays excused under -ignore_covered_err";
  is branch([1, 0], ["default", 0])->coverage_state(0), "covered",
    "stale branch path forgiven under -ignore_covered_err";
}

sub test_ignore_covered_err_class () {
  is statement(1, "ignore_covered_err")->coverage_state, "covered",
    "stale statement forgiven by its own class";
  is statement(0, "ignore_covered_err")->coverage_state, "excused",
    "excused statement stays excused with the class";
  is branch([1, 0], ["ignore_covered_err", 0])->coverage_state(0), "covered",
    "stale branch path forgiven by its own class";
}

sub main () {
  test_scalar_states;
  test_indexed_states;
  test_ignore_covered_err;
  test_ignore_covered_err_class;
  done_testing;
}

main

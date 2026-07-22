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

use Test::More import => [qw( done_testing is skip )];

use Devel::Cover::Html_Common qw( coverage_class default_thresholds );

sub test_default_banding () {
  is coverage_class(0),     "c0", "0% is c0";
  is coverage_class(74.99), "c0", "just below c0 threshold";
  is coverage_class(75),    "c1", "at c0 threshold";
  is coverage_class(89.99), "c1", "just below c1 threshold";
  is coverage_class(90),    "c2", "at c1 threshold";
  is coverage_class(99.99), "c2", "just below c2 threshold";
  is coverage_class(100),   "c3", "100% is c3";
  is coverage_class("n/a"), "na", "n/a maps to na";
  is coverage_class(undef), "na", "undef maps to na";
}

sub test_custom_thresholds () {
  my $t = { c0 => 25, c1 => 50, c2 => 75 };
  is coverage_class(20, $t), "c0", "custom c0";
  is coverage_class(30, $t), "c1", "custom c1";
  is coverage_class(60, $t), "c2", "custom c2";
  is coverage_class(80, $t), "c3", "custom c3";
}

sub test_default_thresholds_copy () {
  my $d = default_thresholds;
  $d->{c0} = 1;
  is default_thresholds->{c0}, 75, "defaults are not shared state";
}

# Runs last: get_options mutates module-level threshold state.
sub test_html_subtle_honours_thresholds () {
  is Devel::Cover::Report::Html_subtle::cvg_class(80), "covered75",
    "default thresholds: 80% is covered75";

  local @ARGV = ();
  Devel::Cover::Report::Html_subtle->get_options(
    { option => {}, report_c0 => 85, report_c1 => 95, report_c2 => 100 });
  is Devel::Cover::Report::Html_subtle::cvg_class(80), "uncovered",
    "custom c0: 80% is uncovered";
  is Devel::Cover::Report::Html_subtle::cvg_class(90), "covered75",
    "custom c1: 90% is covered75";
  is Devel::Cover::Report::Html_subtle::cvg_class(97), "covered90",
    "custom c2: 97% is covered90";
  is Devel::Cover::Report::Html_subtle::cvg_class(100), "covered",
    "100% is covered";
}

test_default_banding;
test_custom_thresholds;
test_default_thresholds_copy;

SKIP: {
  skip "Template not available", 5
    unless eval { require Devel::Cover::Report::Html_subtle; 1 };
  test_html_subtle_honours_thresholds;
}

done_testing;

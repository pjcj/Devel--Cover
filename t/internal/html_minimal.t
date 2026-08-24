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

use Test::More import => [qw( done_testing is ok )];
use Devel::Cover::Mcdc                 ();  ## no perlimports
use Devel::Cover::Report::Html_minimal ();

sub _mock_cond ($class, $hits, $info, $observed = undef) {
  bless [$hits, $info, undef, $observed], "Devel::Cover::$class"
}

# Worked example `($a && $b) || $c` with the four observed input vectors from
# docs/technical/mcdc.md.  Cross-product synthesis produces five composite rows;
# one is the (1,0,0) phantom that no test executed. After observed-vector
# override the phantom must render covered=0 so the truth-table view agrees with
# the MC/DC view.
sub test_truth_table_honours_observed_vectors () {
  my @cond = (
    _mock_cond(
      "Condition_and_3",
      [1, 1, 1],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    _mock_cond(
      "Condition_or_3",
      [1, 1, 1],
      { type    => "or_3", left    => '$a && $b', op => "||",   right => '$c' },
      { "1|1|X" => 1,      "1|0|1" => 1,          "0|X|1" => 1, "0|X|0" => 1 },
    ),
  );

  my @tts = Devel::Cover::Report::Html_minimal::truth_table(@cond);
  is @tts, 1, "single composite truth table from worked example";

  my ($tt, $expr) = $tts[0]->@*;
  is $expr, '$a && $b || $c', "composite expression label";

  my %covered;
  for my $row (@$tt) {
    $covered{ join "|", $row->inputs } = $row->covered ? 1 : 0;
  }

  is $covered{"1|1|X"}, 1, "observed (1,1,X) covered";
  is $covered{"1|0|1"}, 1, "observed (1,0,1) covered";
  is $covered{"0|X|1"}, 1, "observed (0,X,1) covered";
  is $covered{"0|X|0"}, 1, "observed (0,X,0) covered";

  ok exists $covered{"1|0|0"}, "phantom (1,0,0) row rendered";
  is $covered{"1|0|0"}, 0, "phantom (1,0,0) not covered";
}

# A compound decision (>= 3 atomics) with no observed vectors is an unverified
# cross-product synthesis, so the minimal reporter must render none of its rows
# covered, agreeing with Html_crisp on void/boolean-context compound decisions.
sub test_void_compound_renders_uncovered () {
  my @cond = (
    _mock_cond(
      "Condition_and_3",
      [1, 1, 1],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
    _mock_cond(
      "Condition_or_3",
      [1, 1, 1],
      { type => "or_3", left => '$a && $b', op => "||", right => '$c' },
    ),
  );

  my @tts = Devel::Cover::Report::Html_minimal::truth_table(@cond);
  my ($tt) = $tts[0]->@*;

  my @covered = map { $_->covered ? 1 : 0 } @$tt;
  ok !(grep { $_ } @covered),
    "unproven compound rows render uncovered without observed vectors";
}

# Tab stops must be measured on the source text, not on the escaped markup,
# or the entities lengthen the line and shift the expansion.
sub test_tab_stops_measure_source_columns () {
  my $e = \&Devel::Cover::Report::Html_minimal::escape_HTML;
  is $e->("abcd\tX"), "abcd&nbsp;&nbsp;&nbsp;&nbsp;X",
    "tab after plain text reaches column 8";
  is $e->("a<b\tX"), "a&lt;b&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;X",
    "tab after an escaped character reaches column 8";
  is $e->("a<b\tX\nc&d"), "a&lt;b&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;X\nc&amp;d",
    "per-line escaping matches whole-text escaping";
}

sub _mock_mcdc ($hits, $unc = undef) {
  bless [$hits, { text => '$a || $b', labels => ["a", "b"] }, $unc],
    "Devel::Cover::Mcdc"
}

# A stale atomic - run despite its marker - is an error, so it must not
# take the covered class. An excused atomic is not an error and keeps it.
sub test_mcdc_atomic_classes () {
  my $sclass = \&Devel::Cover::Report::Html_minimal::sclass;
  my $marked = _mock_mcdc([1, 0], [1, 1]);
  is $sclass->($marked, 0), "c0", "stale atomic takes the uncovered class";
  is $sclass->($marked, 1), "c3", "excused atomic keeps the covered class";
  my $plain = _mock_mcdc([1, 0]);
  is $sclass->($plain, 0), "c3", "covered atomic keeps the covered class";
  is $sclass->($plain, 1), "c0", "uncovered atomic takes the uncovered class";
}

sub main () {
  test_truth_table_honours_observed_vectors;
  test_void_compound_renders_uncovered;
  test_tab_stops_measure_source_columns;
  test_mcdc_atomic_classes;
  done_testing;
}

main;

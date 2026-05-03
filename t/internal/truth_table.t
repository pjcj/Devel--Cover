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
use Devel::Cover::Truth_Table ();

# Mock criterion responding to ->get($line); subclasses
# Devel::Cover::DB::Criterion so $self->truth_table($line) dispatches
# to the method defined in Truth_Table.pm.
{

  package MockCriterion;
  our @ISA = ("Devel::Cover::DB::Criterion");
  sub new ($class, $by_line) { bless $by_line, $class }
  sub get ($self, $line)     { $self->{$line} }
}

sub _mock_cond ($class, $hits, $info, $observed = undef) {
  bless [$hits, $info, undef, $observed], "Devel::Cover::$class"
}

# Worked-example shape `($a && $b) || $c` with all logop hits and the
# four observed input vectors from docs/technical/mcdc.md.  Synthesis
# produces five composite rows; one of them - (1,0,0) - is a cross-
# product phantom that no test actually executed.  After observed-
# vector override the phantom must render covered=0 so the truth-table
# view agrees with the MC/DC view.
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

  my $crit = MockCriterion->new({ 7 => \@cond });
  my @tts  = $crit->truth_table(7);
  is @tts, 1, "single composite truth table from worked-example shape";

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

sub main () {
  test_truth_table_honours_observed_vectors;
  done_testing;
}

main;

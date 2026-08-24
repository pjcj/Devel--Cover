#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# The class of an uncoverable marker must reach err_chk for truth-table rows,
# so a per-outcome class:ignore_covered_err excuses a stale marker in the
# crisp and JSON reports as it already does in the text report (GH-750).

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is is_deeply skip )];

use Devel::Cover::Condition_and_3 ();
use Devel::Cover::Condition_table ();

my $Has_json = eval "require JSON::MaybeXS; 1"
  && eval "require Devel::Cover::Report::Json; 1";
my $Has_html = eval "require HTML::Entities; 1"
  && eval "require Devel::Cover::Report::Html_crisp; 1";

package Mock::Criterion {
  sub new      ($class, $loc) { bless { loc => $loc }, $class }
  sub location ($self, $line) { $self->{loc} }
}

package Mock::File {
  sub new ($class, $criterion) { bless { criterion => $criterion }, $class }
  sub condition ($self)        { $self->{criterion} }
}

## no critic (Subroutines::ProtectPrivateSubs)

sub mock_condition ($hits, $unc) {
  bless [$hits, { type => "and_3", left => '$a', op => "&&", right => '$b' },
    $unc],
    "Devel::Cover::Condition_and_3"
}

sub table_for ($hits, $unc) {
  my ($table)
    = Devel::Cover::Condition_table->for_line([mock_condition($hits, $unc)]);
  $table
}

sub test_row_carries_class () {
  my $table = table_for([1, 1, 1], [("ignore_covered_err") x 3]);
  is $_->uncoverable, "ignore_covered_err", "row carries the class"
    for $table->rows;
}

sub test_unmarked_rows_stay_false () {
  my $table = table_for([1, 0, 1], [undef, "default", undef]);
  is_deeply [map $_->uncoverable, $table->rows], [0, "default", 0],
    "only the marked outcome carries a class";
}

sub test_json_ignore_covered_err_excuses () {
  SKIP: {
    skip "JSON::MaybeXS not available", 2 unless $Has_json;
    my $table = table_for([1, 1, 1], [("ignore_covered_err") x 3]);
    my $tt    = Devel::Cover::Report::Json::_truth_table($table);
    is $tt->{percentage}, 100, "json: stale ignore_covered_err rows excused";
    is_deeply [map $_->{uncoverable}, $tt->{rows}->@*], [1, 1, 1],
      "json: the emitted uncoverable field stays 0 or 1";
  }
}

sub test_json_default_class_still_errors () {
  SKIP: {
    skip "JSON::MaybeXS not available", 1 unless $Has_json;
    my $table = table_for([1, 1, 1], [("default") x 3]);
    my $tt    = Devel::Cover::Report::Json::_truth_table($table);
    is $tt->{percentage}, 0, "json: stale default rows still error";
  }
}

sub test_crisp_ignore_covered_err_excuses () {
  SKIP: {
    skip "HTML::Entities not available", 2 unless $Has_html;
    my $f = Mock::File->new(Mock::Criterion->new(
      [mock_condition([1, 1, 1], [("ignore_covered_err") x 3])]
    ));
    my ($tt) = Devel::Cover::Report::Html_crisp::line_truth_tables($f, 2);
    is grep($_->{error}, $tt->{rows}->@*), 0,
      "crisp: stale ignore_covered_err rows excused";
    my $g = Mock::File->new(Mock::Criterion->new(
      [mock_condition([1, 1, 1], [("default") x 3])]));
    my ($gt) = Devel::Cover::Report::Html_crisp::line_truth_tables($g, 2);
    is grep($_->{error}, $gt->{rows}->@*), 3,
      "crisp: stale default rows still error";
  }
}

sub main () {
  test_row_carries_class;
  test_unmarked_rows_stay_false;
  test_json_ignore_covered_err_excuses;
  test_json_default_class_still_errors;
  test_crisp_ignore_covered_err_excuses;
}

main;
done_testing;

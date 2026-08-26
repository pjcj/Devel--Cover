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

use Test::More import => [qw( diag done_testing is is_deeply like )];

use Devel::Cover::DB           ();
use Devel::Cover::Report::Text ();

sub db_with_runs (%runs) {
  Devel::Cover::DB->new(runs => {%runs}, _structure => 0)
}

sub print_runs_output ($db) {
  my $output;
  {
    open my $fh, ">", \$output or die "Cannot open scalar ref: $!";
    local *STDOUT = $fh;
    Devel::Cover::Report::Text::print_runs($db, undef);
    close $fh or die "Cannot close scalar ref: $!";
  }
  $output // ""
}

sub test_no_warnings_without_start () {
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_ };
  my $db   = db_with_runs(r1 => {}, r2 => {});
  my @keys = $db->run_keys;
  is @keys, 2, "both runs returned";
  is @warnings, 0, "no warnings from run_keys without start values"
    or diag join "", @warnings;
}

sub test_deterministic_tie_order () {
  local $SIG{__WARN__} = sub { };
  my $db = db_with_runs(map { ("run$_" => {}) } 1 .. 8);
  is_deeply [$db->run_keys], [reverse map "run$_", 1 .. 8],
    "tied runs sort by key rather than hash order";
}

sub test_started_run_sorts_first () {
  local $SIG{__WARN__} = sub { };
  my $db = db_with_runs(r1 => { start => 100 }, r2 => {});
  my ($first) = $db->run_keys;
  is $first, "r1", "a run with a start time sorts before one without";
}

sub test_distinct_starts_keep_order () {
  my $db = db_with_runs(
    r1 => { start => 100 },
    r2 => { start => 200 },
    r3 => { start => 300 },
  );
  is_deeply [$db->run_keys], [qw( r3 r2 r1 )], "run_keys are newest first";
  is_deeply [map $_->{start}, $db->runs], [300, 200, 100],
    "runs follow run_keys order";
}

sub test_print_runs_without_comparison_warnings () {
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_ };
  my $db = db_with_runs(
    r1 => { run => "a", perl => "5.20.0", OS => "linux" },
    r2 => { run => "b", perl => "5.20.0", OS => "linux" },
  );
  print_runs_output($db);
  is grep(/numeric comparison/, @warnings), 0,
    "no comparison warnings from print_runs without start values"
    or diag join "", @warnings;
}

sub test_print_runs_oldest_first () {
  my $db = db_with_runs(
    r1 =>
      { run => "newer", perl => "p", OS => "o", start => 200, finish => 201 },
    r2 =>
      { run => "older", perl => "p", OS => "o", start => 100, finish => 101 },
  );
  like print_runs_output($db), qr/older.*newer/s, "runs print oldest first";
}

sub main () {
  test_no_warnings_without_start;
  test_deterministic_tie_order;
  test_started_run_sorts_first;
  test_distinct_starts_keep_order;
  test_print_runs_without_comparison_warnings;
  test_print_runs_oldest_first;
  done_testing;
}

main;

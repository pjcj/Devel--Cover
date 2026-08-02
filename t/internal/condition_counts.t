#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# _condition_counts must return a fresh counts array and leave the array it is
# given untouched.  The array it receives is the live per-op counts array from
# the XS side, so reordering it in place corrupts the source data if it is ever
# read again, and storing the returned array by reference aliases the run data
# to it.  The fixture runs under cover so Devel::Cover is loaded, calls the
# function directly and records what it saw.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is )];

use Devel::Cover::Test::Internal qw( write_script run_under_cover );

my $Source = <<'PERL';
use strict;
use warnings;

use B qw( OPf_KIDS svref_2object );

sub find_op {
  my ($op, $name) = @_;
  return unless $$op;
  return $op if $op->name eq $name;
  return unless $op->flags & OPf_KIDS;
  for (my $kid = $op->first; $$kid; $kid = $kid->sibling) {
    my $found = find_op($kid, $name);
    return $found if $found;
  }
  return
}

sub fmt { join ",", map { defined $_ ? $_ : "u" } @{ $_[0] } }

my $or_op = find_op(svref_2object(sub { $_[0] || $_[1] })->ROOT, "or")
  or die "no or op found";
my $and_op = find_op(svref_2object(sub { $_[0] && $_[1] })->ROOT, "and")
  or die "no and op found";

open my $out, ">", "$0.out" or die "Cannot write $0.out: $!";
for my $case (
  [ "xor",   [ 10, 20, 30, 40, 50 ],      "xor", undef   ],
  [ "or",    [ 1, 2, 3, 4 ],              "or",  $or_op  ],
  [ "and",   [ 1, 2, 3, 4 ],              "and", $and_op ],
  [ "or_c5", [ 1, 2, 3, 4, undef, 1 ],    "or",  $or_op  ],
) {
  my ($name, $c, $type, $op) = @$case;
  my ($counts, $count, $collapsed)
    = Devel::Cover::_condition_counts($c, $type, $op);
  print $out join("|", $name, fmt($c), fmt($counts), $count, $collapsed), "\n";
}
close $out or die "Cannot close $0.out: $!";
PERL

my %Case;

sub _setup () {
  return if %Case;
  my $script = write_script("condition_counts.pl", $Source);
  run_under_cover($script, "condition_counts", criteria => ["condition"]);
  open my $fh, "<", "$script.out" or die "Cannot read $script.out: $!";
  while (my $line = <$fh>) {
    chomp $line;
    my ($name, @fields) = split /\|/, $line;
    $Case{$name}->@{qw( orig counts count collapsed )} = @fields;
  }
  close $fh or die "Cannot close $script.out: $!";
}

sub test_original_arrays_untouched () {
  is $Case{xor}{orig}, "10,20,30,40,50", "xor leaves its counts array alone";
  is $Case{or}{orig},  "1,2,3,4",        "or leaves its counts array alone";
  is $Case{and}{orig}, "1,2,3,4",        "and leaves its counts array alone";
  is $Case{or_c5}{orig}, "1,2,3,4,u,1",
    "short-circuit or leaves its counts array alone";
}

sub test_rows_reordered () {
  is $Case{xor}{counts},   "40,30,50,20", "xor rows reordered";
  is $Case{or}{counts},    "4,3,2",       "or rows reordered";
  is $Case{and}{counts},   "4,2,3",       "and rows reordered";
  is $Case{or_c5}{counts}, "4,5", "short-circuit or collapses to two rows";
}

sub test_row_counts () {
  is $Case{xor}{count},   4, "xor has four rows";
  is $Case{or}{count},    3, "or has three rows";
  is $Case{and}{count},   3, "and has three rows";
  is $Case{or_c5}{count}, 2, "short-circuit or has two rows";
}

sub test_void_collapsed_flag () {
  is $Case{or}{collapsed},    0, "or is not collapsed";
  is $Case{or_c5}{collapsed}, 1, "short-circuit or is collapsed";
}

sub main () {
  _setup;
  test_original_arrays_untouched;
  test_rows_reordered;
  test_row_counts;
  test_void_collapsed_flag;
  done_testing;
}

main;

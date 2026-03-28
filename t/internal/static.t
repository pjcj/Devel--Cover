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
use lib $FindBin::Bin, qw( ./lib ./blib/lib ./blib/arch );

use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [ qw( done_testing is ok plan ) ];

eval { require PPI; 1 } or do {
  plan skip_all => "PPI not available";
  exit;
};

use Devel::Cover::Static ();

my $Tmpdir = tempdir(CLEANUP => 1);

sub write_file ($name, $content) {
  my $path = File::Spec->catfile($Tmpdir, $name);
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
  $path
}

# Minimal module: package, use strict/warnings, one sub with two
# statements. DC would count: 6 include stmts (3 per use) + 1
# compound header (none) + 2 simple stmts = 8 total.
sub test_minimal () {
  my $file = write_file("Minimal.pm", <<'EOPERL');
package Minimal;
use strict;
use warnings;

sub hello {
  my $name = shift;
  print "hello $name\n";
}

1
EOPERL

  my $counts = Devel::Cover::Static::count_criteria($file);
  ok defined $counts, "minimal: returns counts";
  is $counts->{statement},  8, "minimal: 8 statements";
  is $counts->{branch},     0, "minimal: 0 branch outcomes";
  is $counts->{condition},  0, "minimal: 0 condition outcomes";
  is $counts->{subroutine}, 3, "minimal: 3 subs (1 user + 2 BEGIN)";
  is $counts->{pod},        1, "minimal: 1 pod-coverable sub";
}

# Branches: if/elsif/else, unless, ternary.
# DC branch outcomes = 2 per decision point.
sub test_branches () {
  my $file = write_file("Branchy.pm", <<'EOPERL');
package Branchy;
use strict;
use warnings;

sub check {
  my $x = shift;
  my $out;
  if ($x > 10) {
    $out = "big";
  } elsif ($x > 0) {
    $out = "small";
  } else {
    $out = "non-positive";
  }
  print "$out\n";
}

sub toggle {
  my $flag = shift;
  my $val  = 0;
  unless ($flag) {
    $val = 99;
  }
  return $val;
}

sub label {
  my $x      = shift;
  my $result = $x > 5 ? "high" : "low";
  return $result;
}

1
EOPERL

  my $counts = Devel::Cover::Static::count_criteria($file);
  ok defined $counts, "branches: returns counts";

  # if/elsif = 2 decisions, unless = 1, ternary = 1 => 4 decisions
  is $counts->{branch}, 8, "branches: 8 outcomes (4 decisions x 2)";

  # check: my $x, my $out, $out=big, $out=small, $out=non-pos,
  #   print = 6 simple + 1 compound hdr = 7
  # toggle: my $flag, my $val, $val=99, return = 4 simple +
  #   1 compound hdr = 5
  # label: my $x, my $result, return = 3 simple
  # includes: 6
  # total: 7+5+3+6 = 21
  is $counts->{statement},  21, "branches: 21 statements";
  is $counts->{subroutine}, 5,  "branches: 5 subs (3 user + 2 BEGIN)";
  is $counts->{pod},        3,  "branches: 3 pod-coverable subs";
}

# For loop - DC does not count a range-for as a branch, but it does
# count the for header as a statement.
sub test_loops () {
  my $file = write_file("Loopy.pm", <<'EOPERL');
package Loopy;
use strict;
use warnings;

sub total {
  my $n   = shift;
  my $sum = 0;
  for my $i (1 .. $n) {
    $sum += $i;
  }
  return $sum;
}

1
EOPERL

  my $counts = Devel::Cover::Static::count_criteria($file);
  ok defined $counts, "loops: returns counts";

  # for-range: 0 branch decisions (DC doesn't count range-for)
  is $counts->{branch}, 0, "loops: 0 branch outcomes for range-for";

  # my $n, my $sum, $sum+=, return = 4 simple + 1 compound hdr + 6
  # include = 11
  is $counts->{statement},  11, "loops: 11 statements";
  is $counts->{subroutine}, 3,  "loops: 3 subs (1 user + 2 BEGIN)";
}

# Pod coverage: total = number of named user subs (excluding BEGIN).
sub test_pod () {
  my $file = write_file("Documented.pm", <<'EOPERL');
package Documented;
use strict;
use warnings;

=encoding utf8

=head1 NAME

Documented - a test module

=head2 foo

Does foo.

=cut

sub foo {
  my $x = shift;
  print "$x\n";
}

sub bar {
  my $y = shift;
  return $y;
}

1
EOPERL

  my $counts = Devel::Cover::Static::count_criteria($file);
  ok defined $counts, "pod: returns counts";
  is $counts->{pod}, 2, "pod: 2 pod-coverable subs (foo, bar)";
}

# Condition coverage: && || // and or xor with RHS filtering.
# Constant/flow-control RHS gives 2 outcomes, normal gives 3,
# xor always gives 4.
sub test_conditions () {
  my $file = write_file("Conditions.pm", <<'EOPERL');
package Conditions;
use strict;
use warnings;

sub normal_and {
  my ($x, $y) = @_;
  my $z = $x && $y;
  return $z;
}

sub normal_or {
  my ($x, $y) = @_;
  my $z = $x || $y;
  return $z;
}

sub normal_dor {
  my ($x, $y) = @_;
  my $z = $x // $y;
  return $z;
}

sub flow_control {
  my $x = shift;
  $x or die "missing";
  $x || return;
  $x // warn "undef";
  $x && next;
  open my $fh, "<", $x or die "open: $!";
}

sub const_rhs {
  my $x = shift;
  my $y = $x || "default";
  my $z = $x // 42;
  my $w = $x && undef;
}

sub xor_op {
  my ($a, $b) = @_;
  my $c = $a xor $b;
  return $c;
}

1
EOPERL

  my $counts = Devel::Cover::Static::count_criteria($file);
  ok defined $counts, "conditions: returns counts";

  # normal_and: $x && $y -> 3 outcomes
  # normal_or: $x || $y -> 3 outcomes
  # normal_dor: $x // $y -> 3 outcomes
  # flow_control: or die -> 2, || return -> 2, // warn -> 2,
  #   && next -> 2, or die -> 2 = 5 x 2 = 10
  # const_rhs: || "default" -> 2, // 42 -> 2, && undef -> 2
  #   = 3 x 2 = 6
  # xor_op: xor -> 4
  # total: 9 + 10 + 6 + 4 = 29
  is $counts->{condition}, 29, "conditions: 29 condition outcomes";
}

# Nonexistent file returns undef.
sub test_missing_file () {
  my $counts = Devel::Cover::Static::count_criteria("/nonexistent/file.pm");
  ok !defined $counts, "missing file: returns undef";
}

sub main () {
  test_minimal;
  test_branches;
  test_loops;
  test_conditions;
  test_pod;
  test_missing_file;
  done_testing;
}

main;

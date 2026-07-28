#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# "# uncoverable condition when:<inputs>" marks the truth-table row whose
# operand values match the pattern, as shown in the report - 0, 1 or X for
# an operand never evaluated.  It reaches every row of every op, including
# xor's fourth row, which no type word addresses (GH-481).

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is is_deeply like ok )];

use Devel::Cover::Test::Internal
  qw( parse_comments run_under_cover warnings_from write_script );

sub covered_when ($label, $source) {
  my $script = write_script("$label.pl", $source);
  my ($db, $path)
    = run_under_cover($script, $label, criteria => ["statement", "condition"]);
  my $warnings = warnings_from { $db->cover };
  ($db->cover, $warnings, $path)
}

sub test_when_patterns_parse () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable condition when:00
# uncoverable condition when:1x,00 count:2
$n++;
PERL
  is @$warnings, 0, "parse: no warnings";
  is_deeply $unc->{digest}{condition}{4}, [
      [["when:00", "default", ""]],
      [["when:1X", "default", ""], ["when:00", "default", ""]],
    ],
    "parse: patterns are kept, lists expand and x is upcased";
}

sub test_when_restrictions () {
  my ($unc, $warnings, $path) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable branch when:00
# uncoverable condition left when:00
# uncoverable condition when:2
$n++;
PERL
  is @$warnings, 3, "restrictions: one warning per comment";
  my $branch = qr/parsing uncoverable branch at \Q$path\E/;
  my $cond   = qr/parsing uncoverable condition at \Q$path\E/;
  like $warnings->[0], qr/Attribute when applies only to condition $branch:2/,
    "restrictions: non-condition criterion warns";
  like $warnings->[1], qr/Attribute when conflicts with a type word $cond:3/,
    "restrictions: conflict with a type word warns";
  like $warnings->[2],
    qr/Invalid attribute when:2 parsing uncoverable condition at \Q$path\E:4/,
    "restrictions: malformed pattern warns";
  ok !exists $unc->{digest}, "restrictions: nothing is recorded";
}

sub test_when_reaches_the_fourth_xor_row () {
  my ($cover, $warnings, $path) = covered_when("xor_row", <<'PERL');
my ($t, $f) = (1, 0);
# uncoverable condition when:00
my $r = ($t xor $f);
PERL
  is @$warnings, 0, "xor: no warnings";
  my $op = $cover->file($path)->criterion("condition")->location(3)->[0];
  ok $op->uncoverable(3),   "xor: fourth row marked";
  ok !$op->uncoverable($_), "xor: row @{[ $_ + 1 ]} untouched" for 0 .. 2;
}

sub test_when_matches_the_op_rows () {
  my ($cover, $warnings, $path) = covered_when("and_rows", <<'PERL');
my ($t, $f) = (1, 0);
# uncoverable condition when:0X,11
my $r = $t && $f;
PERL
  is @$warnings, 0, "and: no warnings";
  my $op = $cover->file($path)->criterion("condition")->location(3)->[0];
  ok $op->uncoverable(0),  "and: 0X marks the short-circuit row";
  ok $op->uncoverable(2),  "and: 11 marks the both-true row";
  ok !$op->uncoverable(1), "and: 10 row untouched";
}

sub test_when_without_matching_row_warns () {
  my ($cover, $warnings, $path) = covered_when("no_row", <<'PERL');
my ($t, $f) = (1, 0);
# uncoverable condition when:01
my $r = $t && $f;
PERL
  is @$warnings, 1, "no row: one warning";
  like $warnings->[0],
    qr/Uncoverable condition when:01 does not apply at \Q$path\E:3/,
    "no row: warning names the pattern";
  my $op = $cover->file($path)->criterion("condition")->location(3)->[0];
  ok !$op->uncoverable($_), "no row: row @{[ $_ + 1 ]} untouched" for 0 .. 2;
}

sub main () {
  test_when_patterns_parse;
  test_when_restrictions;
  test_when_reaches_the_fourth_xor_row;
  test_when_matches_the_op_rows;
  test_when_without_matching_row_warns;
}

main;
done_testing;

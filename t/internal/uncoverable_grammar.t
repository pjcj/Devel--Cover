#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# Strict validation of uncoverable comment details: unsupported criteria,
# unknown types, misspelt or misplaced attributes and malformed counts all
# warn and drop the comment instead of being silently misread (GH-481).

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is is_deeply like ok )];

use Devel::Cover::Test::Internal qw( parse_comments );

sub test_unsupported_criteria_warn () {
  my ($unc, $warnings, $path) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable time
# uncoverable total
$n++;
PERL
  is @$warnings, 2, "unsupported: one warning per comment";
  like $warnings->[0],
    qr/Unsupported criterion parsing uncoverable time at \Q$path\E:2/,
    "unsupported: time warns";
  like $warnings->[1],
    qr/Unsupported criterion parsing uncoverable total at \Q$path\E:3/,
    "unsupported: total warns";
  ok !exists $unc->{digest}, "unsupported: nothing is recorded";
}

sub test_unknown_type_drops () {
  my ($unc, $warnings, $path) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable branch frobnicate
$n++;
PERL
  is @$warnings, 1, "unknown type: one warning";
  like $warnings->[0],
    qr/Unknown type frobnicate parsing uncoverable branch at \Q$path\E:2/,
    "unknown type: warning names the type";
  ok !exists $unc->{digest}, "unknown type: nothing is recorded";
}

sub test_invalid_attributes_warn () {
  my ($unc, $warnings, $path) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable statement cont:2
# uncoverable branch true clazz:x
# uncoverable statement stray
# uncoverable branch true extra
# uncoverable statement count:1..
$n++;
PERL
  is @$warnings, 5, "invalid attribute: one warning per comment";
  like $warnings->[0],
    qr/Invalid attribute cont:2 parsing uncoverable statement at \Q$path\E:2/,
    "invalid attribute: count typo warns";
  like $warnings->[1],
    qr/Invalid attribute clazz:x parsing uncoverable branch at \Q$path\E:3/,
    "invalid attribute: class typo warns";
  like $warnings->[2],
    qr/Invalid attribute stray parsing uncoverable statement at \Q$path\E:4/,
    "invalid attribute: stray word warns";
  like $warnings->[3],
    qr/Invalid attribute extra parsing uncoverable branch at \Q$path\E:5/,
    "invalid attribute: word after type warns";
  my $at = qr/parsing uncoverable statement at \Q$path\E:6/;
  like $warnings->[4], qr/Invalid attribute count:1\.\. $at/,
    "invalid attribute: malformed count warns";
  ok !exists $unc->{digest}, "invalid attribute: nothing is recorded";
}

sub test_pair_restrictions () {
  my ($unc, $warnings, $path) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable condition left pair:1
# uncoverable mcdc all pair:2
# uncoverable mcdc pair:0
$n++;
PERL
  is @$warnings, 3, "pair: one warning per comment";
  my $cond = qr/parsing uncoverable condition at \Q$path\E/;
  my $mcdc = qr/parsing uncoverable mcdc at \Q$path\E/;
  like $warnings->[0], qr/Attribute pair applies only to mcdc $cond:2/,
    "pair: non-mcdc criterion warns";
  like $warnings->[1], qr/Attribute pair conflicts with all $mcdc:3/,
    "pair: conflict with all warns";
  like $warnings->[2], qr/Invalid pair:0 \(pairs are numbered from 1\) $mcdc:4/,
    "pair: zero warns";
  ok !exists $unc->{digest}, "pair: nothing is recorded";
}

sub test_double_spaced_attributes_parse () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable statement  class:ignore_covered_err
$n++;
PERL
  is @$warnings, 0, "double space: no warnings";
  is_deeply $unc->{digest}{statement}{3},
    [[[undef, "ignore_covered_err", ""]]], "double space: class still parses";
}

sub test_count_lists_expand () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable statement count:2,4..6
$n++;
PERL
  is @$warnings, 0, "count list: no warnings";
  my $slot = [[undef, "default", ""]];
  is_deeply $unc->{digest}{statement}{3},
    [undef, $slot, undef, $slot, $slot, $slot],
    "count list: ranges expand to slots";
}

sub test_note_consumes_the_rest () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable branch false class:x note:looks like cont:2 typo
$n++;
PERL
  is @$warnings, 0, "note: no warnings";
  is_deeply $unc->{digest}{branch}{3}, [[[1, "x", "looks like cont:2 typo"]]],
    "note: takes everything after note:";
}

sub test_attribute_order_is_free () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable statement class:c count:2
$n++;
PERL
  is @$warnings, 0, "order: no warnings";
  is_deeply $unc->{digest}{statement}{3}, [undef, [[undef, "c", ""]]],
    "order: class before count parses";
}

sub main () {
  test_unsupported_criteria_warn;
  test_unknown_type_drops;
  test_invalid_attributes_warn;
  test_pair_restrictions;
  test_double_spaced_attributes_parse;
  test_count_lists_expand;
  test_note_consumes_the_rest;
  test_attribute_order_is_free;
}

main;
done_testing;

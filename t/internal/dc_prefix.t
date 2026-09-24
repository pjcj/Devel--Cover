#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# The "dc" prefix introduces every source annotation.  "dc uncoverable" is
# the canonical spelling of the uncoverable comment and the bare
# "uncoverable" form stays as an alias with its old, lenient behaviour.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is is_deeply like ok )];

use Devel::Cover::Test::Internal qw( parse_comments );

sub test_dc_uncoverable_matches_legacy () {
  my ($dc, $dc_warnings) = parse_comments(<<'PERL');
my $n = 1;
# dc uncoverable statement count:2 class:ignore_covered_err
# dc uncoverable branch true note:never taken
$n++; $n++;
PERL
  my ($legacy, $legacy_warnings) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable statement count:2 class:ignore_covered_err
# uncoverable branch true note:never taken
$n++; $n++;
PERL
  is @$dc_warnings,     0, "dc uncoverable: no warnings";
  is @$legacy_warnings, 0, "legacy uncoverable: no warnings";
  is_deeply $dc, $legacy, "dc uncoverable: parses as the legacy form";
  is_deeply $dc->{digest}{statement}{4},
    [undef, [[undef, "ignore_covered_err", ""]]],
    "dc uncoverable: attributes are recorded";
}

sub test_dc_uncoverable_inline () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
$n++; # dc uncoverable statement
PERL
  is @$warnings, 0, "inline: no warnings";
  is_deeply $unc->{digest}{statement}{2}, [[[undef, "default", ""]]],
    "inline: applies to the line it is on";
}

sub test_unknown_verb_warns () {
  my ($unc, $warnings, $path) = parse_comments(<<'PERL');
my $n = 1;
# dc frobnicate statement
$n++;
PERL
  is @$warnings, 1, "unknown verb: one warning";
  like $warnings->[0], qr/Unknown annotation frobnicate at \Q$path\E:2/,
    "unknown verb: warning names the verb";
  ok !exists $unc->{digest}, "unknown verb: nothing is recorded";
}

sub test_dc_unsupported_criterion_warns () {
  my ($unc, $warnings, $path) = parse_comments(<<'PERL');
my $n = 1;
# dc uncoverable frob
$n++;
PERL
  is @$warnings, 1, "dc unsupported criterion: one warning";
  like $warnings->[0],
    qr/Unsupported criterion parsing uncoverable frob at \Q$path\E:2/,
    "dc unsupported criterion: warning names the word";
  ok !exists $unc->{digest}, "dc unsupported criterion: nothing is recorded";
}

sub test_legacy_unknown_word_is_ignored () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable frob
$n++;
PERL
  is @$warnings, 0, "legacy unknown word: no warning";
  ok !exists $unc->{digest}, "legacy unknown word: nothing is recorded";
}

sub test_noreturn_is_a_known_verb () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
# dc noreturn usage_die
$n++;
PERL
  is @$warnings, 0, "noreturn: no warning";
  ok !exists $unc->{digest}, "noreturn: records no uncoverable data";
}

sub test_dc_must_open_the_comment () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
# see dc uncoverable statement
# dc: uncoverable statement
$n++;
PERL
  is @$warnings, 0, "not first text: no warning";
  ok !exists $unc->{digest}, "not first text: nothing is recorded";
}

sub main () {
  test_dc_uncoverable_matches_legacy;
  test_dc_uncoverable_inline;
  test_unknown_verb_warns;
  test_dc_unsupported_criterion_warns;
  test_legacy_unknown_word_is_ignored;
  test_noreturn_is_a_known_verb;
  test_dc_must_open_the_comment;
}

main;
done_testing;

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# Uncoverable comments on their own line must attach to the next line of
# code, skipping blank lines and ordinary comments (GH-481).  One with
# nothing but blanks or comments after it must warn, not vanish.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is is_deeply like ok )];

use Devel::Cover::Test::Internal qw( parse_comments );

sub test_attaches_to_next_line () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable branch true
if ($n == 0) { }
PERL
  is @$warnings, 0, "adjacent: no warnings";
  is_deeply $unc->{digest}{branch}{3}, [[[0, "default", ""]]],
    "adjacent: comment attaches to the code line";
}

sub test_skips_blank_line () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable branch true

if ($n == 0) { }
PERL
  is @$warnings, 0, "blank: no warnings";
  ok !exists $unc->{digest}{branch}{3},
    "blank: nothing attaches to the blank line";
  is_deeply $unc->{digest}{branch}{4}, [[[0, "default", ""]]],
    "blank: comment attaches to the code line";
}

sub test_skips_ordinary_comment () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable branch true
# just an ordinary comment
if ($n == 0) { }
PERL
  is @$warnings, 0, "comment: no warnings";
  ok !exists $unc->{digest}{branch}{3},
    "comment: nothing attaches to the comment line";
  is_deeply $unc->{digest}{branch}{4}, [[[0, "default", ""]]],
    "comment: comment attaches to the code line";
}

sub test_comment_after_code_is_recognised () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
$n++;  # uncoverable statement
PERL
  is @$warnings, 0, "after code: no warnings";
  is_deeply $unc->{digest}{statement}{2}, [[[undef, "default", ""]]],
    "after code: comment applies to its own line";
}

sub test_quoted_syntax_in_prose_is_ignored () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
# see the docs for "# uncoverable branch true" comments
if ($n == 0) { }
PERL
  is @$warnings, 0, "prose: no warnings";
  ok !exists $unc->{digest}{branch}, "prose: quoted syntax creates nothing";
}

sub test_trailing_annotation_warns () {
  my ($unc, $warnings, $path) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable branch true

PERL
  is @$warnings, 1, "trailing: one warning";
  like $warnings->[0], qr/unmatched uncoverable comments/,
    "trailing: warning names the problem";
  ok !exists $unc->{digest}{branch}, "trailing: nothing attaches";
}

sub main () {
  test_attaches_to_next_line;
  test_skips_blank_line;
  test_skips_ordinary_comment;
  test_comment_after_code_is_recognised;
  test_quoted_syntax_in_prose_is_ignored;
  test_trailing_annotation_warns;
}

main;
done_testing;

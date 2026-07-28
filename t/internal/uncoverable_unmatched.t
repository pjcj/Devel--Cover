#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# An uncoverable comment can attach to a line and still match nothing there -
# a branch comment above an elsif whose branches anchor at the opening if, a
# count past the constructs on the line, or the wrong criterion entirely.
# Such comments must warn at report time instead of vanishing (GH-481).

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is like )];

use Devel::Cover::Test::Internal qw( run_under_cover write_script );

{
  no feature "signatures";

  sub warnings_from (&) {
    my ($code) = @_;
    my $err = "";
    open my $save_err, ">&", \*STDERR or die "Cannot dup STDERR: $!";
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">", \$err or die "Cannot redirect STDERR: $!";
    $code->();
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">&", $save_err or die "Cannot restore STDERR: $!";
    [split /(?<=\n)/, $err]
  }
}

sub cover_warnings ($label, $source, %opts) {
  my $script = write_script("$label.pl", $source);
  my ($db, $path) = run_under_cover($script, $label, %opts);
  my $warnings = warnings_from { $db->cover };
  ($warnings, $path)
}

sub test_comment_above_elsif_warns () {
  my ($warnings, $path)
    = cover_warnings("elsif", <<'PERL', criteria => ["statement", "branch"]);
my $n = 0;
my $r;
if ($n == 0) {
  $r = "a";
# uncoverable branch true
} elsif ($n == 1) {
  $r = "b";
}
PERL
  is @$warnings, 1, "elsif: one warning";
  like $warnings->[0], qr/Unmatched uncoverable branch comment at \Q$path\E:6/,
    "elsif: warning gives criterion and file:line";
}

sub test_count_overshoot_warns () {
  my ($warnings, $path)
    = cover_warnings("overshoot",
      <<'PERL', criteria => ["statement", "branch"]);
my $n = 0;
# uncoverable branch true count:2
if ($n == 0) { $n++ }
PERL
  is @$warnings, 1, "overshoot: one warning";
  like $warnings->[0],
    qr/Unmatched uncoverable branch comment at \Q$path\E:3 count:2/,
    "overshoot: warning gives the count";
}

sub test_wrong_criterion_warns () {
  my ($warnings, $path) = cover_warnings(
    "criterion", <<'PERL', criteria => ["statement", "branch", "condition"]);
my $n = 1;
# uncoverable condition left
my $r = $n + 1;
PERL
  is @$warnings, 1, "criterion: one warning";
  like $warnings->[0],
    qr/Unmatched uncoverable condition comment at \Q$path\E:3/,
    "criterion: warning names the criterion";
}

sub test_matched_comment_is_quiet () {
  my ($warnings)
    = cover_warnings("matched", <<'PERL', criteria => ["statement", "branch"]);
my $n = 1;
# uncoverable branch false
if ($n) { $n++ }
PERL
  is @$warnings, 0, "matched: no warnings";
}

sub test_uncollected_criterion_is_quiet () {
  my ($warnings)
    = cover_warnings("uncollected",
      <<'PERL', criteria => ["statement", "branch"]);
my $n = 1;
# uncoverable condition left
my $r = $n + 1;
PERL
  is @$warnings, 0, "uncollected: no warning for uncollected criterion";
}

sub test_warnings_are_sorted () {
  my ($warnings) = cover_warnings(
    "sorted", <<'PERL', criteria => ["statement", "branch", "condition"]);
my $n = 0;
# uncoverable condition left
# uncoverable branch true
my $r = $n + 1;
PERL
  is @$warnings, 2, "sorted: two warnings";
  like $warnings->[0], qr/uncoverable branch comment/,
    "sorted: branch warning first";
  like $warnings->[1], qr/uncoverable condition comment/,
    "sorted: condition warning second";
}

sub test_silent_suppresses () {
  my $script = write_script("silent.pl", <<'PERL');
my $n = 1;
# uncoverable condition left
my $r = $n + 1;
PERL
  my ($db) = run_under_cover(
    $script, "silent", criteria => ["statement", "branch", "condition"],
  );
  my $warnings = warnings_from {
    local $Devel::Cover::Silent = 1;
    $db->cover;
  };
  is @$warnings, 0, "silent: no warnings";
}

sub main () {
  test_comment_above_elsif_warns;
  test_count_overshoot_warns;
  test_wrong_criterion_warns;
  test_matched_comment_is_quiet;
  test_uncollected_criterion_is_quiet;
  test_warnings_are_sorted;
  test_silent_suppresses;
}

main;
done_testing;

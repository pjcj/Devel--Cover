#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# "# uncoverable branch all" marks every element of the branch, and the same
# for condition and mcdc.  This is the natural comment for an elsif that can
# never run, where naming each outcome describes something that never
# happens (GH-481).

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

sub covered_all ($label, $source, %opts) {
  my $script = write_script("$label.pl", $source);
  my ($db, $path) = run_under_cover($script, $label, %opts);
  my $warnings = warnings_from { $db->cover };
  ($db->cover, $warnings, $path)
}

sub test_parse_all_types () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable branch all
# uncoverable condition all count:2
# uncoverable mcdc all
$n++;
PERL
  is @$warnings, 0, "parse: no warnings";
  is_deeply $unc->{digest}{branch}{5}, [[[undef, "default", ""]]],
    "parse: branch all gives an undefined type";
  is_deeply $unc->{digest}{condition}{5}, [undef, [[undef, "default", ""]]],
    "parse: condition all count:2 fills the second slot";
  is_deeply $unc->{digest}{mcdc}{5}, [[[undef, "default", ""]]],
    "parse: mcdc all matches the bare form";
}

sub test_bare_multi_element_comments_warn () {
  my ($unc, $warnings, $path) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable branch
# uncoverable condition
# uncoverable mcdc
$n++;
PERL
  is @$warnings, 3, "bare: one warning per comment";
  like $warnings->[$_],
    qr/Missing type parsing uncoverable \w+ at \Q$path\E:@{[ $_ + 2 ]}/,
    "bare: warning gives criterion and file:line"
    for 0 .. 2;
  ok !exists $unc->{digest}, "bare: nothing is recorded";
}

sub test_mcdc_pair_needs_no_type () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable mcdc pair:1
$n++;
PERL
  is @$warnings, 0, "pair: no warnings";
  is_deeply $unc->{digest}{mcdc}{3}, [[[0, "default", ""]]],
    "pair: still parses without a type word";
}

sub test_unknown_type_still_warns () {
  my ($unc, $warnings, $path) = parse_comments(<<'PERL');
my $n = 1;
# uncoverable branch frobnicate
$n++;
PERL
  is @$warnings, 1, "unknown type: one warning";
  like $warnings->[0], qr/Unknown type frobnicate/,
    "unknown type: warning names the type";
}

sub test_branch_all_excuses_an_elsif () {
  my ($cover, $warnings, $path)
    = covered_all("branch_all", <<'PERL', criteria => ["statement", "branch"]);
my $n = 0;
my $r;
# uncoverable branch false count:1
# uncoverable branch all count:2
if ($n == 0) {
  $r = "a";
} elsif ($n == 1) {
  $r = "b";  # uncoverable statement
}
PERL
  is @$warnings, 0, "branch all: no warnings";
  my $branches = $cover->file($path)->criterion("branch")->location(5);
  my $elsif    = $branches->[1];
  ok $elsif->uncoverable(0), "branch all: true element marked";
  ok $elsif->uncoverable(1), "branch all: false element marked";
  is $elsif->error, 0, "branch all: no errors on the elsif";
}

sub test_condition_all_excuses_an_op () {
  my ($cover, $warnings, $path) = covered_all(
    "condition_all", <<'PERL', criteria => ["statement", "condition"]);
my ($a, $b) = (1, 0);
my $r;
if ($a) {
  $r = 1;
  # uncoverable condition all
} elsif ($a && $b) {
  $r = 2;  # uncoverable statement
}
PERL
  is @$warnings, 0, "condition all: no warnings";
  my $conditions = $cover->file($path)->criterion("condition")->location(6);
  my $op         = $conditions->[0];
  ok $op->uncoverable($_), "condition all: element $_ marked"
    for 0 .. $op->total - 1;
  is $op->error, 0, "condition all: no errors on the op";
}

sub main () {
  test_parse_all_types;
  test_bare_multi_element_comments_warn;
  test_mcdc_pair_needs_no_type;
  test_unknown_type_still_warns;
  test_branch_all_excuses_an_elsif;
  test_condition_all_excuses_an_op;
}

main;
done_testing;

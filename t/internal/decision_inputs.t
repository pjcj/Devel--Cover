#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# Per-execution decision input vectors are recorded at runtime via XS and
# appear in the cover_db at $Run{decision_inputs}{$file}[$n]{$vector_key} =
# count.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Cwd        qw( abs_path );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is is_deeply ok subtest )];

use Devel::Cover::DB ();

my $Tmpdir = tempdir(CLEANUP => 1);

sub write_script ($name, $content) {
  my $path = File::Spec->catfile($Tmpdir, $name);
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
  $path
}

sub run_under_cover ($script, $label, @criteria) {
  my $cover_db   = File::Spec->catdir($Tmpdir, "cover_db_$label");
  my $abs_tmpdir = abs_path($Tmpdir);
  my $coverage   = @criteria ? "-coverage," . join(",", @criteria) . "," : "";
  my @cmd        = (
    $^X, "-Iblib/lib", "-Iblib/arch",
    "-MDevel::Cover=-db,$cover_db,-silent,1,${coverage}+select,$abs_tmpdir",
    $script,
  );
  system(@cmd) == 0 or die "Failed to run script under Devel::Cover: @cmd";

  my $db = Devel::Cover::DB->new(db => $cover_db);
  $db->merge_runs;
  my $real_path = abs_path($script);
  ($db, $real_path)
}

sub decision_inputs_for ($db, $file) {
  for my $run (values $db->{runs}->%*) {
    return $run->{decision_inputs}{$file} if $run->{decision_inputs}{$file};
  }
  return;
}

sub test_simple_and () {
  my $script = write_script("simple_and.pl", <<'PERL');
my @r;
sub two { my ($p, $q) = @_; push @r, $p && $q }
two(1, 1);
two(1, 0);
two(0, 1);
two(0, 0);
PERL

  my ($db, $path) = run_under_cover($script, "simple_and");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for simple_and";
  is @$di, 1, "one decision recorded";

  is_deeply $di->[0], { "1|1" => 1, "1|0" => 1, "0|X" => 2 },
    "vectors and counts: (1,1), (1,0), and two short-circuits to (0,X)";
}

sub test_worked_example () {
  my $script = write_script("worked.pl", <<'PERL');
my @r;
sub may_edit {
  my ($is_owner, $unlocked, $is_admin) = @_;
  push @r, ($is_owner && $unlocked) || $is_admin;
}
may_edit(1, 1, 1);
may_edit(1, 0, 1);
may_edit(0, 0, 1);
may_edit(0, 0, 0);
PERL

  my ($db, $path) = run_under_cover($script, "worked");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for worked example";

  # Find the entry recording the outer || root (3 columns; 4 distinct
  # observed vectors).  Inner && entries have no decision_inputs.
  my @recorded = grep defined, @$di;
  is @recorded, 1, "exactly one root recorded (outer ||)";

  is_deeply $recorded[0],
    { "1|1|X" => 1, "1|0|1" => 1, "0|X|1" => 1, "0|X|0" => 1 },
    "four distinct observed vectors, no phantom (1,0,0)";
}

sub test_repeated_observation () {
  my $script = write_script("repeated.pl", <<'PERL');
my @r;
sub two { my ($p, $q) = @_; push @r, $p && $q }
two(1, 1) for 1 .. 3;
two(0, 0) for 1 .. 5;
PERL

  my ($db, $path) = run_under_cover($script, "repeated");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for repeated";

  is_deeply $di->[0], { "1|1" => 3, "0|X" => 5 },
    "counts accumulate across executions";
}

sub test_no_inputs_without_mcdc () {
  my $script = write_script("no_mcdc.pl", <<'PERL');
my @r;
sub two { my ($p, $q) = @_; push @r, $p && $q }
two(1, 1);
two(1, 0);
two(0, 1);
two(0, 0);
PERL

  my ($db, $path) = run_under_cover(
    $script, "no_mcdc", qw( statement branch condition subroutine )
  );
  my $di = decision_inputs_for($db, $path);
  ok !$di, "decision_inputs absent when mcdc not selected";
}

sub test_add_condition_cross_run_merge () {
  my $db = bless {}, "Devel::Cover::DB";
  my $cc = {};
  my $sc = [[42, { type => "or_3" }]];
  my $uc = { 42 => [[]] };

  $db->add_condition($cc, $sc, [[1, 0, 2]], $uc, [{ "1|1" => 1, "1|0" => 2 }]);
  $db->add_condition($cc, $sc, [[3, 4, 0]], $uc, [{ "1|1" => 5, "0|X" => 7 }]);

  is_deeply $cc->{42}[0][0], [4, 4, 2],
    "hit counts sum across runs (slots 0-2)";

  is_deeply $cc->{42}[0][3], { "1|1" => 6, "1|0" => 2, "0|X" => 7 },
    "observed-vector counts merged: shared key sums, new keys appended";
}

sub test_add_condition_xor_four_slot_merge () {
  my $db = bless {}, "Devel::Cover::DB";
  my $cc = {};
  my $sc = [[7, { type => "xor_4" }]];
  my $uc = { 7 => [[]] };

  $db->add_condition($cc, $sc, [[1, 2, 3, 4]], $uc);
  $db->add_condition($cc, $sc, [[5, 6, 7, 8]], $uc);

  is_deeply $cc->{7}[0][0], [6, 8, 10, 12],
    "xor four-slot hit counts (slots 0-3) sum across runs";
}

sub main () {
  subtest "simple two-leaf and"    => \&test_simple_and;
  subtest "worked example"         => \&test_worked_example;
  subtest "repeated observation"   => \&test_repeated_observation;
  subtest "no inputs without mcdc" => \&test_no_inputs_without_mcdc;
  subtest "cross-run merge"        => \&test_add_condition_cross_run_merge;
  subtest "xor four-slot merge"    => \&test_add_condition_xor_four_slot_merge;

  done_testing;
}

main;

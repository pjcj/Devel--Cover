#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use lib "t/lib";

use Devel::Cover::Test::Internal qw( write_script run_under_cover );

use Test::More import => [qw( done_testing is ok plan )];

if ($^O eq "MSWin32") {
  plan skip_all => "exec has spawn semantics on Windows";
  exit;
}

sub covered_file ($script, $label) {
  my ($db, $path)
    = run_under_cover($script, $label, criteria => ["statement", "branch"]);
  my $file = $db->cover->file($path);
  ok $file, "$label: the program is in the database" or return;
  ($db, $file)
}

sub run_count ($db) {
  my @runs = $db->runs;
  scalar @runs
}

sub statement_count ($file, $line) {
  my $loc = $file->statement->location($line);
  $loc ? $loc->[0]->covered : undef
}

sub test_failed_exec_keeps_collecting () {
  my $script = write_script("exec_failed.pl", <<'PERL');
my $x = 1;
exec "/no/such/command" or warn "exec failed\n";
$x++;
my $y = $x * 2;
PERL
  my ($db, $file) = covered_file($script, "exec_failed") or return;
  is statement_count($file, 3), 1, "the statement after the failed exec ran";
  is statement_count($file, 4), 1, "and so did the one after that";
  my $branch = $file->branch->location(2);
  ok $branch, "the exec's or branch is collected" or return;
  is grep($_, $branch->[0]->values), 1, "one leg of the or branch ran";
  is run_count($db), 2, "the exec-time and END-time runs are both written";
}

sub test_successful_exec_unchanged () {
  my $script = write_script("exec_ok.pl", <<'PERL');
my $x = 1;
exec $^X, "-e", "exit 0";
my $y = 2;
PERL
  my ($db, $file) = covered_file($script, "exec_ok") or return;
  is statement_count($file, 1), 1, "the statement before the exec ran";
  is statement_count($file, 3), 0, "the statement after the exec did not";
  is run_count($db), 1, "a successful exec writes one run";
}

sub main () {
  test_failed_exec_keeps_collecting;
  test_successful_exec_unchanged;
  done_testing;
}

main;

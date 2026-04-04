#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# Test that the get_condition_dor hijack is recognised in runops_cover.
#
# When //= doesn't short-circuit (LHS is undef), cover_logop() hijacks
# right->op_next with get_condition_dor.  If the hijacked op is
# OP_NEXTSTATE, the hijack check in runops_cover must recognise it;
# otherwise the statement is counted twice - once before
# get_condition_dor runs and once after it restores the original ppaddr.
#
# runops_cover is only active when replace_ops is off, so this test
# uses -replace_ops,0.

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
use Test::More import => [ qw( done_testing is ok ) ];

use Devel::Cover::DB ();

my $Tmpdir = tempdir(CLEANUP => 1);

sub write_script ($name, $content) {
  my $path = File::Spec->catfile($Tmpdir, $name);
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
  $path
}

# Run a script under Devel::Cover with runops_cover (replace_ops off),
# then return ($cover, $real_path) where $real_path is the absolute
# symlink-resolved path that Devel::Cover stores for the script.
sub run_under_cover ($script, $label) {
  my $cover_db = File::Spec->catdir($Tmpdir, "cover_db_$label");
  my $abs_tmpdir = abs_path($Tmpdir);
  my @cmd = (
    $^X, "-Iblib/lib", "-Iblib/arch",
    "-MDevel::Cover=-db,$cover_db,-silent,1,-replace_ops,0"
      . ",+select,$abs_tmpdir",
    $script,
  );
  system(@cmd) == 0
    or die "Failed to run script under Devel::Cover: @cmd";

  my $db = Devel::Cover::DB->new(db => $cover_db);
  $db->merge_runs;
  my $cover = $db->cover;

  # Devel::Cover resolves symlinks (e.g. /tmp -> /private/tmp on macOS)
  my $real_path = abs_path($script);
  ($cover, $real_path)
}

# //= with undef LHS: the NEXTSTATE for the following line gets hijacked
# with get_condition_dor.  When the hijack check misses it, that line's
# statement count is 2 instead of 1.
sub test_dorassign_undef () {
  my $script = write_script("dorassign_undef.pl", <<'PERL');
my $x;
$x //= 42;
my $y = 1;
PERL

  my ($cover, $path) = run_under_cover($script, "dorassign_undef");
  my $file = $cover->file($path);
  ok $file, "dorassign_undef: coverage data found";

  my $stmts = $file->criterion("statement");
  ok $stmts, "dorassign_undef: statement criterion present";

  # Line 3 (my $y = 1) has its NEXTSTATE hijacked by //= on line 2.
  my $loc = $stmts->location(3);
  ok $loc && @$loc, "dorassign_undef: statement found on line 3";
  is $loc->[0][0], 1,
    "dorassign_undef: line 3 counted once (not doubled by missed hijack)";
}

# //= with defined LHS (short-circuits): no hijack occurs, so no bug.
# This is a control case to confirm that the test infrastructure works.
sub test_dorassign_defined () {
  my $script = write_script("dorassign_defined.pl", <<'PERL');
my $x = 1;
$x //= 42;
my $y = 1;
PERL

  my ($cover, $path) = run_under_cover($script, "dorassign_defined");
  my $file = $cover->file($path);
  ok $file, "dorassign_defined: coverage data found";

  my $stmts = $file->criterion("statement");
  ok $stmts, "dorassign_defined: statement criterion present";

  my $loc = $stmts->location(3);
  ok $loc && @$loc, "dorassign_defined: statement found on line 3";
  is $loc->[0][0], 1,
    "dorassign_defined: line 3 counted once (control case)";
}

# //= inside a loop amplifies the miscount: each iteration where LHS is
# undef adds an extra statement count.
sub test_dorassign_loop () {
  my $script = write_script("dorassign_loop.pl", <<'PERL');
for my $i (0 .. 2) {
  my $x;
  $x //= $i;
  my $y = 1;
}
PERL

  my ($cover, $path) = run_under_cover($script, "dorassign_loop");
  my $file = $cover->file($path);
  ok $file, "dorassign_loop: coverage data found";

  my $stmts = $file->criterion("statement");
  ok $stmts, "dorassign_loop: statement criterion present";

  # Line 4 (my $y = 1) runs 3 times. With the bug, each iteration
  # where $x is undef (all 3) adds a spurious count, giving 6.
  my $loc = $stmts->location(4);
  ok $loc && @$loc, "dorassign_loop: statement found on line 4";
  is $loc->[0][0], 3,
    "dorassign_loop: line 4 counted 3 times (not 6)";
}

sub main () {
  test_dorassign_undef;
  test_dorassign_defined;
  test_dorassign_loop;
  done_testing;
}

main;

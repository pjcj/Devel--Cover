#!/usr/bin/env perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# Test that the get_condition_dor hijack is recognised in runops_cover.

# When //= doesn't short-circuit (LHS is undef), cover_logop() hijacks
# right->op_next with get_condition_dor.  If the hijacked op is OP_NEXTSTATE,
# the hijack check in runops_cover must recognise it; otherwise the statement is
# counted twice - once before get_condition_dor runs and once after it restores
# the original ppaddr.

# runops_cover is only active when replace_ops is off, so this test uses
# -replace_ops,0.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is ok )];

use Devel::Cover::Test::Internal qw( write_script run_under_cover );

sub check_stmt_count ($label, $code, $line, $expected) {
  my $script = write_script("$label.pl", $code);
  my ($db, $path)
    = run_under_cover($script, $label, options => ["-replace_ops,0"]);
  my $file = $db->cover->file($path);
  ok $file, "$label: coverage data found";

  my $stmts = $file->criterion("statement");
  ok $stmts, "$label: statement criterion present";

  my $loc = $stmts->location($line);
  ok $loc && @$loc, "$label: statement found on line $line";
  is $loc->[0][0], $expected, "$label: line $line count is $expected";
}

sub main () {
  # //= with undef LHS: the NEXTSTATE for the following line gets hijacked
  # with get_condition_dor.  When the hijack check misses it, that line's
  # statement count is 2 instead of 1.
  check_stmt_count("dorassign_undef", <<'PERL', 3, 1);
my $x;
$x //= 42;
my $y = 1;
PERL

  # //= with defined LHS (short-circuits): no hijack, so no bug.
  # Control case to confirm the test infrastructure works.
  check_stmt_count("dorassign_defined", <<'PERL', 3, 1);
my $x = 1;
$x //= 42;
my $y = 1;
PERL

  # //= inside a loop amplifies the miscount: each iteration where LHS is
  # undef adds a spurious count (3 iterations x 2 = 6 instead of 3).
  check_stmt_count("dorassign_loop", <<'PERL', 4, 3);
for my $i (0 .. 2) {
  my $x;
  $x //= $i;
  my $y = 1;
}
PERL

  done_testing;
}

main;

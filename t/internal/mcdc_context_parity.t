#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# MC/DC context parity: the same logical decision must record the same truth
# table regardless of the evaluation context it sits in.  A decision in
# scalar-assignment context (its value forced into a scalar) records one
# unified table over all its atomic conditions; this test asserts that the
# explicit-return and implicit-return (last-statement) forms record the SAME
# table structure.  The driver calls the sub in void context, so the return
# forms evaluate the decision in void context - that is the real variable
# under test, not the return keyword (option-4 Phase 1 finding, recorded in
# llm/plans/GH-478-mcdc/phase1_root_cause.md).
#
# Today they do not match: a logop that runs void is collapsed to a degenerate
# narrow table and its MC/DC vectors are skipped, so explicit return yields one
# narrow table and implicit return decomposes into separate per-logop tables.
# The differential assertions are therefore wrapped in a TODO block until void
# compound decisions record their full structure (Phase 2).  The reference
# assertions (scalar-assignment records one unified table) pass today and
# establish the correct target.

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
use Test::More import => [qw( done_testing is is_deeply subtest $TODO )];

use Devel::Cover::DB ();

my $Tmpdir = tempdir(CLEANUP => 1);

# Decisions under test.  Each is a genuine multi-condition decision; D1-D3 have
# four atomic positions (D3 is coupled, reusing $a), D4 is a three-condition
# nested decision.
my %Decision = (
  D1 => '($a && $b) || ($c && $d)',  # or of and-pairs
  D2 => '($a || $b) && ($c || $d)',  # and of or-pairs
  D3 => '($a && $b) || ($a && $c)',  # coupled
  D4 => '$a && ($b || $c)',          # nested / mixed precedence
);

# Context wrappers.  scalar_assign is the reference; the others must match it.
my %Context = (
  scalar_assign   => sub ($expr) { "my \$r = $expr; \$r" },
  explicit_return => sub ($expr) { "return $expr" },
  implicit_return => sub ($expr) { "$expr" },
);

sub write_script ($name, $content) {
  my $path = File::Spec->catfile($Tmpdir, $name);
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
  $path
}

sub run_under_cover ($script, $label) {
  my $cover_db   = File::Spec->catdir($Tmpdir, "cover_db_$label");
  my $abs_tmpdir = abs_path($Tmpdir);
  my @cmd        = (
    $^X,
    "-Iblib/lib",
    "-Iblib/arch",
    "-MDevel::Cover=-db,$cover_db,-silent,1,"
      . "-coverage,condition,-coverage,mcdc,+select,$abs_tmpdir",
    $script,
  );
  system(@cmd) == 0 or die "Failed to run script under Devel::Cover: @cmd";

  my $db = Devel::Cover::DB->new(db => $cover_db);
  $db->merge_runs;
  ($db, abs_path($script))
}

# Drive a single decision in a single context across all 16 input tuples, then
# return its recorded MC/DC table structure as a sorted list of label counts -
# one entry per recorded table.  A unified four-condition decision yields [4];
# a decision split into two tables yields, say, [1, 2].
sub table_structure ($op, $context) {
  my $expr = $Decision{$op};
  my $body = $Context{$context}->($expr);
  my $code = <<PERL;
sub decision { my (\$a, \$b, \$c, \$d) = \@_; $body }
for my \$v (0 .. 15) {
  decision(map { (\$v >> \$_) & 1 } 0 .. 3);
}
PERL

  my $label = "${op}_${context}";
  my ($db, $path) = run_under_cover(write_script("$label.pl", $code), $label);
  my $mcdc = $db->cover->file($path)->{mcdc} // {};

  my @counts;
  for my $line (keys %$mcdc) {
    for my $decision ($mcdc->{$line}->@*) {
      push @counts, scalar $decision->labels->@*;
    }
  }
  [sort { $a <=> $b } @counts]
}

for my $op (sort keys %Decision) {
  subtest "context parity: $op ($Decision{$op})" => sub {
    my $reference = table_structure($op, "scalar_assign");

    # Reference: scalar assignment records exactly one unified table, the
    # target the other contexts must reach.
    is @$reference, 1, "scalar-assignment records a single unified table";

    # Explicit return: the void-collapsed outer logop is recorded (as the
    # degenerate form) and MC/DC rebuilds it to the full structure.
    is_deeply table_structure($op, "explicit_return"), $reference,
      "explicit return records the same table as scalar assignment";

    # Implicit return (last statement): the outer logop feeds leavesub
    # directly, so in void context it is never recorded at all - the inner
    # logops surface as separate roots and the decision cannot be rebuilt.
    # Recording the absent outer logop needs an XS recorder change.
    {
      local $TODO = "implicit return: the void outer logop feeds leavesub "
        . "directly and is never recorded";

      is_deeply table_structure($op, "implicit_return"), $reference,
        "implicit return records the same table as scalar assignment";
    }
  };
}

done_testing;

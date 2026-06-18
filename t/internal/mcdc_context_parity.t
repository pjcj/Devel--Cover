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
# forms evaluate the decision in void context - that is the real variable under
# test, not the return keyword.
#
# All three contexts now match.  Explicit return records the outer logop as a
# condition in the collapsed void form, which MC/DC promotes back to the full
# structure.  Implicit return records the outer logop as a branch, whose decision
# structure is kept separately so MC/DC rebuilds the same unified table; see
# L<Devel::Cover::DB/Compound decision roots>.

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
use Test::More import => [qw( done_testing is is_deeply subtest )];

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

    # Implicit return (last statement): the outer logop is recorded as a branch,
    # but its decision structure is kept so MC/DC rebuilds the unified table.
    is_deeply table_structure($op, "implicit_return"), $reference,
      "implicit return records the same table as scalar assignment";
  };
}

done_testing;

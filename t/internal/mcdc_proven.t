#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# Proven MC/DC for compound decision roots.  An implicit-return (last-statement)
# compound decision is recorded as a branch, and its unified MC/DC table is
# rebuilt from a separately recorded decision root; see
# L<Devel::Cover::DB/Compound decision roots>.  When the sub is called for its
# value, the decision's input vectors are observed in full, so the rebuilt table
# must report the same proven MC/DC coverage as the reference scalar-assignment
# form, and that coverage must be stable across repeated runs (no duplicated
# table).
#
# Note: a last-statement decision in a sub called in VOID context cannot observe
# its right operand, so it stays honestly unproven (0%); the driver here calls
# every sub in scalar context so the decision is evaluated for its value.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is ok subtest )];

use Devel::Cover::Test::Internal qw( write_script run_under_cover );

my $Decision = '($a && $b) || ($c && $d)';

# Drive the decision in $context over the input tuples in @$tuples, $runs times
# into one coverage database, then return its single MC/DC table's covered and
# total counts.
my $Call = 0;

sub run_mcdc ($context, $tuples, $runs) {
  my $body
    = $context eq "scalar_assign" ? "my \$r = $Decision; \$r" : "$Decision";
  my $list = join ", ", map "[$_->[0], $_->[1], $_->[2], $_->[3]]", @$tuples;
  # Capture the result so the sub is called in scalar (value) context.
  my $code = <<PERL;
sub decision { my (\$a, \$b, \$c, \$d) = \@_; $body }
my \$sink;
\$sink = decision(\@\$_) for ($list);
PERL

  my $label  = "${context}_${runs}_" . $Call++;
  my $script = write_script("$label.pl", $code);
  my ($db, $path);
  for (1 .. $runs) {
    ($db, $path)
      = run_under_cover($script, $label, criteria => [qw( condition mcdc )]);
  }
  my $mcdc = $db->cover->file($path)->{mcdc} // {};

  my @tables = map $_->@*, values %$mcdc;
  is @tables, 1, "$context ($runs run) records a single unified table";
  my $t = $tables[0];
  ($t->covered, $t->total)
}

# All 16 input tuples.
my @All = map { my $v = $_; [map { ($v >> $_) & 1 } 0 .. 3] } 0 .. 15;

subtest "single-run proven coverage matches scalar assignment" => sub {
  my ($s_cov, $s_tot) = run_mcdc("scalar_assign",   \@All, 1);
  my ($i_cov, $i_tot) = run_mcdc("implicit_return", \@All, 1);

  ok $s_cov > 0,
    "scalar assignment proves some MC/DC coverage ($s_cov/$s_tot)";
  is $i_tot, $s_tot, "implicit return reports the same total";
  is $i_cov, $s_cov, "implicit return proves the same MC/DC coverage";
};

subtest "coverage is stable across repeated runs" => sub {
  # Two runs over the same script must not duplicate the table and must prove
  # the same coverage as a single run.
  my ($one_cov, $one_tot) = run_mcdc("implicit_return", \@All, 1);
  my ($two_cov, $two_tot) = run_mcdc("implicit_return", \@All, 2);
  is $two_tot, $one_tot, "two runs report the same total";
  is $two_cov, $one_cov, "two runs prove the same coverage (no duplication)";
};

done_testing;

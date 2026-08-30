#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# Devel::Cover records coverage two ways - with -replace_ops 1 it swaps each
# op's ppaddr for a wrapper, and with -replace_ops 0 it runs its own runops
# loop.  The two must agree, so each fixture runs under both settings and the
# databases are compared.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use File::Spec   ();
use File::Temp   qw( tempdir );
use Scalar::Util qw( reftype );
use Test::More import => [qw( done_testing is_deeply )];

use Devel::Cover::Test::Internal qw( write_script run_under_cover );

my @Criteria = qw( statement branch condition subroutine );

my %Fixture = (
  padrange_excluded => <<'PERL',
require Excluded;
Excluded::poke();
my ($p, $q) = (1, 2);
if ($p < $q) { my ($r, $s) = (3, 4) }
PERL
  conditionals => <<'PERL',
my $x = 1;
my $y = 0;
my $r = $x && $y ? 1 : 2;
$r = $x || $y;
$r = $y // $x;
PERL
  loops => <<'PERL',
my $total = 0;
for my $i (1 .. 3) { $total += $i }
while ($total > 3) { $total-- }
PERL
  subs => <<'PERL',
sub called   { my ($a, $b) = @_; $a + $b }
sub uncalled { my ($a, $b) = @_; $a - $b }
called(1, 2);
PERL
);

sub write_excluded_module () {
  my $dir = tempdir(CLEANUP => 1);
  my $mod = File::Spec->catfile($dir, "Excluded.pm");
  open my $fh, ">", $mod or die "Cannot write $mod: $!";
  print $fh <<'PERL';
package Excluded;
my ($a, $b) = (1, 2);
sub poke { my ($x, $y) = (3, 4); return }
1;
PERL
  close $fh or die "Cannot close $mod: $!";
  $dir
}

# Op addresses in the condition metadata differ between any two processes,
# so they say nothing about parity and are removed before comparing.
sub scrub ($node) {
  my $type = reftype($node) // "";
  if ($type eq "HASH") {
    delete @$node{ grep /addr$/, keys %$node };
    scrub($_) for values %$node;
  } elsif ($type eq "ARRAY") {
    scrub($_) for @$node;
  }
  $node
}

sub file_cover ($script, $label, @options) {
  my ($db, $path) = run_under_cover(
    $script, $label,
    criteria => [@Criteria],
    options  => [@options],
  );
  scrub($db->cover->file($path))
}

sub test_parity ($name) {
  my $source = $Fixture{$name};
  $source = "use lib '" . write_excluded_module() . "';\n$source"
    if $name eq "padrange_excluded";
  my $script   = write_script("$name.pl", $source);
  my $replaced = file_cover($script, "${name}_r1");
  my $runops   = file_cover($script, "${name}_r0", "-replace_ops,0");
  is_deeply $runops, $replaced, "$name matches across -replace_ops settings";
}

sub main () {
  test_parity $_ for sort keys %Fixture;
  done_testing;
}

main;

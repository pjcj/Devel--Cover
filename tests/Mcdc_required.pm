# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Mcdc_required;

# Top-level code of a required file, run in an eval CV that owns no optree.

my @r;

# Three-atom || at the file's top level, every short-circuit row.
for my $t ([1, 0, 0], [0, 1, 0], [0, 0, 1], [0, 0, 0]) {
  my ($x, $y, $z) = @$t;
  push @r, $x || $y || $z;
}

# Three-atom && under an eval block at the file's top level.
for my $t ([1, 1, 1], [1, 1, 0], [1, 0, 0], [0, 0, 0]) {
  my ($x, $y, $z) = @$t;
  eval { push @r, $x && $y && $z };
}

sub count { scalar @r }

1

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Mcdc::Analyser;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

sub _is_x ($v) { defined $v && $v eq "X" }

sub _concrete_differs ($a, $b) {
  return 0 if _is_x($a) || _is_x($b);
  $a != $b
}

sub _sca_agrees ($a, $b) {
  return 1 if _is_x($a) || _is_x($b);
  $a == $b
}

sub _find_pair ($col, $rows, $ncols, $coupled = undef) {
  for my $i (0 .. $#$rows) {
    for my $j ($i + 1 .. $#$rows) {
      my $a = $rows->[$i];
      my $b = $rows->[$j];
      next if $a->result == $b->result;
      my ($ai, $bi) = ($a->inputs, $b->inputs);
      next unless _concrete_differs($ai->[$col], $bi->[$col]);

      my $ok = 1;
      for my $k (0 .. $ncols - 1) {
        next if $k == $col;
        next if $coupled && $coupled->[$k];
        unless (_sca_agrees($ai->[$k], $bi->[$k])) {
          $ok = 0;
          last;
        }
      }
      return [$i, $j] if $ok;
    }
  }
  undef
}

sub analyse ($class, $table) {
  my @labels = $table->labels;
  my @rows   = grep $_->covered, $table->rows;
  my $ncols  = @labels;

  my %label_count;
  $label_count{$_}++ for @labels;

  my %pairs;
  my @missing;

  for my $col (0 .. $#labels) {
    my $found = _find_pair($col, \@rows, $ncols);
    if (!$found && $label_count{ $labels[$col] } > 1) {
      my @coupled = map $labels[$_] eq $labels[$col], 0 .. $#labels;
      $found = _find_pair($col, \@rows, $ncols, \@coupled);
    }

    if ($found) {
      $pairs{$col} = $found;
    } else {
      push @missing, $labels[$col];
    }
  }

  {
    total     => $ncols,
    satisfied => scalar keys %pairs,
    pairs     => \%pairs,
    missing   => \@missing,
  }
}

"
Maybe the sun's light will be dim
And it won't matter anyhow
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Mcdc::Analyser - MC/DC pair analyser

=head1 SYNOPSIS

 use Devel::Cover::Mcdc::Analyser;

 my $result    = Devel::Cover::Mcdc::Analyser->analyse($table);
 my $total     = $result->{total};
 my $satisfied = $result->{satisfied};
 my @missing   = $result->{missing}->@*;

=head1 DESCRIPTION

Given a L<Devel::Cover::Condition_table::Table> for a single decision, computes
Modified Condition/Decision Coverage (MC/DC) pairs for each atomic condition.

The analyser implements hybrid MC/DC: a unique-cause first pass followed by a
masking fallback for coupled conditions (the same atomic condition appearing
more than once in a decision).  In typical Perl code, where coupling is rare,
hybrid behaves like unique-cause.

C<analyse> returns a hashref with keys:

=over 4

=item C<total>

Total number of atomic conditions in the decision.

=item C<satisfied>

Number of atomic conditions whose independence pair was demonstrated.

=item C<pairs>

Per-atomic record of the pair of rows that demonstrated independence, where one
was found.

=item C<missing>

Arrayref of atomic conditions whose independence pair was not demonstrated.

=back

=head1 SEE ALSO

 Devel::Cover::Mcdc
 Devel::Cover::Condition_table

=head1 LICENCE

Copyright 2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

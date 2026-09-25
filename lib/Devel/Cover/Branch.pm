# Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Branch;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use base "Devel::Cover::Criterion";

sub pad ($self) {
  $self->[0] = [0, 0] unless $self->[0] && $self->[0]->@*;
}

sub uncoverable ($self, $i = undef) {
  defined $i ? $self->[2][$i] : scalar grep $_, $self->[2]->@*;
}

sub covered ($self, $i = undef) {
  defined $i ? $self->[0][$i] : scalar grep $_, $self->[0]->@*;
}

sub total     ($self)     { scalar $self->[0]->@* }
sub value     ($self, $i) { $self->[0][$i] }
sub values    ($self)     { $self->[0]->@* }
sub text      ($self)     { $self->[1]{text} }
sub criterion ($self)     { "branch" }

sub shortname        ($class) { "bran" }
sub detail_criterion ($class) { "branch" }
sub sign_letter      ($class) { "B" }
sub indexed          ($class) { 1 }

sub percentage ($self) {
  my $t = $self->total;
  $t ? int(($t - $self->error) / $t * 100) : 0;
}

sub error ($self, $c = undef) {
  return $self->err_chk($self->covered($c), $self->uncoverable($c))
    if defined $c;
  my $e = 0;
  for my $i (0 .. $self->total - 1) {
    $e++ if $self->err_chk($self->covered($i), $self->uncoverable($i));
  }
  $e;
}

sub calculate_summary ($self, $db, $file) {
  my $s = $db->{summary};
  $self->pad;

  $self->aggregate($s, $file, "total",       $self->total);
  $self->aggregate($s, $file, "uncoverable", $self->uncoverable);
  $self->aggregate($s, $file, "covered",     $self->covered);
  $self->aggregate($s, $file, "error",       $self->error);
}

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Branch - Branch coverage criterion

=head1 SYNOPSIS

 use Devel::Cover::Branch;

=head1 DESCRIPTION

Module for storing branch coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

The entry is C<[counts, information, uncoverable]>. The counts are an
array with the true count first and the false count second. The
information is a hash holding the source text of the condition. The
uncoverable flags are an array with one entry per path.

=head2 pad

Set two zero counts on a branch that has none.

=head2 uncoverable ($i)

Return the uncoverable flag for path C<$i>, or without an index the
number of paths marked uncoverable.

=head2 covered ($i)

Return the count for path C<$i>, or without an index the number of paths
taken.

=head2 total

Return the number of paths.

=head2 value ($i)

Return the count for path C<$i>.

=head2 values

Return the list of counts.

=head2 text

Return the source text of the condition.

=head2 criterion

Return C<branch>.

=head2 shortname

Return C<bran>.

=head2 detail_criterion

Return C<branch>.

=head2 sign_letter

Return C<B>.

=head2 indexed

Return true.

=head2 percentage

Return the share of paths not in error, as an integer. A branch with no
paths gives 0.

=head2 error ($i)

Return whether path C<$i> is in error, or without an index the number of
paths in error.

=head2 calculate_summary ($db, $file)

Pad the counts, then add the total, uncoverable, covered and error counts
to the summary of the database.

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

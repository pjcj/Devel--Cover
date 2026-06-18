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

sub percentage ($self) {
  my $t = $self->total;
  $t ? int($self->covered / $t * 100) : 0;
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

Devel::Cover::Branch - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Branch;

=head1 DESCRIPTION

Module for storing branch coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

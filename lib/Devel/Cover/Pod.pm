# Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Pod;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use base "Devel::Cover::Criterion";

BEGIN { eval "use Pod::Coverage 0.06" }  # We'll use this if it is available.

sub uncoverable ($self) { $self->[2] }
sub covered     ($self) { $self->[0] ? 1 : 0 }
sub total       ($self) { 1 }
sub percentage  ($self) { $self->[0] ? 100 : 0 }
sub error       ($self) { $self->simple_error }
sub criterion   ($self) { "pod" }

sub calculate_summary ($self, $db, $file) {
  return unless $INC{"Pod/Coverage.pm"};

  my $s = $db->{summary};

  $self->aggregate($s, $file, "total",   $self->total);
  $self->aggregate($s, $file, "covered", 1) if $self->covered;
  $self->aggregate($s, $file, "error",   $self->error);
}

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Pod - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Pod;

=head1 DESCRIPTION

Module for storing pod coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

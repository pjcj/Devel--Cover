# Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Condition;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use base "Devel::Cover::Branch";
use Carp ();

sub pad ($self) { $self->[0][$_] ||= 0 for 0 .. $self->count - 1 }

sub text ($self) {
  "$self->[1]{left} $self->[1]{op} $self->[1]{right}";
}

sub type      ($self) { $self->[1]{type} }
sub criterion ($self) { "condition" }

sub shortname        ($class) { "cond" }
sub detail_criterion ($class) { "condition" }
sub sign_letter      ($class) { "C" }
sub count            ($self)  { Carp::confess("count() must be overridden") }
sub headers          ($self)  { Carp::confess("headers() must be overridden") }

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Condition - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Condition;

=head1 DESCRIPTION

Module for storing condition coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

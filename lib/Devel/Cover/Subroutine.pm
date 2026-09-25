# Copyright 2004-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Subroutine;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use base "Devel::Cover::Criterion";

sub uncoverable ($self) { $self->[2] }
sub covered     ($self) { $self->[0] }
sub total       ($self) { 1 }
sub percentage  ($self) { $self->error ? 0 : 100 }
sub error       ($self) { $self->simple_error }
sub name        ($self) { $self->[1] }
sub criterion   ($self) { "subroutine" }

sub shortname        ($class) { "sub" }
sub display_mode     ($class) { "count" }
sub detail_criterion ($class) { "subroutine" }
sub sign_letter      ($class) { "R" }

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Subroutine - Subroutine coverage criterion

=head1 SYNOPSIS

 use Devel::Cover::Subroutine;

=head1 DESCRIPTION

Module for storing subroutine coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

The entry is C<[count, name, uncoverable]>.

=head2 uncoverable

Return the uncoverable flag.

=head2 covered

Return the number of calls, which is true when the subroutine ran.

=head2 total

Return 1.

=head2 percentage

Return 100 when the subroutine is not in error, otherwise 0.

=head2 error

Return the result of C<simple_error> in L<Devel::Cover::Criterion>.

=head2 name

Return the name of the subroutine.

=head2 criterion

Return C<subroutine>.

=head2 shortname

Return C<sub>.

=head2 display_mode

Return C<count>.

=head2 detail_criterion

Return C<subroutine>.

=head2 sign_letter

Return C<R>.

=head1 LICENCE

Copyright 2004-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

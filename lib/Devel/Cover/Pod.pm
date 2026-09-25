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
sub percentage  ($self) { $self->error ? 0 : 100 }
sub error       ($self) { $self->simple_error }
sub criterion   ($self) { "pod" }

sub display_mode     ($class) { "count" }
sub detail_criterion ($class) { "subroutine" }
sub sign_letter      ($class) { "P" }

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Pod - Pod coverage criterion

=head1 SYNOPSIS

 use Devel::Cover::Pod;

=head1 DESCRIPTION

Module for storing pod coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

The entry is C<[covered, name, uncoverable]>. The coverage comes from
L<Pod::Coverage>, which the module loads when it is installed.

=head2 uncoverable

Return the uncoverable flag.

=head2 covered

Return 1 when the subroutine has documentation, otherwise 0.

=head2 total

Return 1.

=head2 percentage

Return 100 when the subroutine is not in error, otherwise 0.

=head2 error

Return the result of C<simple_error> in L<Devel::Cover::Criterion>.

=head2 criterion

Return C<pod>.

=head2 display_mode

Return C<count>.

=head2 detail_criterion

Return C<subroutine>, since pod values link to the subroutine detail page.

=head2 sign_letter

Return C<P>.

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

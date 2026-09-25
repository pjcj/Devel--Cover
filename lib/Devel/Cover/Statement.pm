# Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Statement;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use base "Devel::Cover::Criterion";

sub uncoverable ($self) { $self->[1] }
sub covered     ($self) { $self->[0] }
sub total       ($self) { 1 }
sub percentage  ($self) { $self->error ? 0 : 100 }
sub error       ($self) { $self->simple_error }
sub criterion   ($self) { "statement" }

sub shortname    ($class) { "stmt" }
sub display_mode ($class) { "count" }
sub sign_letter  ($class) { "S" }

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Statement - Statement coverage criterion

=head1 SYNOPSIS

 use Devel::Cover::Statement;

=head1 DESCRIPTION

Module for storing statement coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

The entry is C<[count, uncoverable]>.

=head2 uncoverable

Return the uncoverable flag.

=head2 covered

Return the execution count, which is true when the statement ran.

=head2 total

Return 1.

=head2 percentage

Return 100 when the statement is not in error, otherwise 0.

=head2 error

Return the result of C<simple_error> in L<Devel::Cover::Criterion>.

=head2 criterion

Return C<statement>.

=head2 shortname

Return C<stmt>.

=head2 display_mode

Return C<count>.

=head2 sign_letter

Return C<S>.

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

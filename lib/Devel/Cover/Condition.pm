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

Devel::Cover::Condition - Condition coverage criterion

=head1 SYNOPSIS

 use Devel::Cover::Condition;

=head1 DESCRIPTION

Module for storing condition coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

This is the base class for the C<Devel::Cover::Condition_*> classes. The
entry is C<[counts, information, uncoverable]> as for
L<Devel::Cover::Branch>, with one count per outcome. The information hash
holds the C<left>, C<op> and C<right> source text and the C<type>, such
as C<or_3>, which names the subclass L<Devel::Cover::DB> blesses the
entry into.

=head2 pad

Set every missing count to zero, up to C<count>.

=head2 text

Return the source text of the condition, built from the left operand, the
operator and the right operand.

=head2 type

Return the condition type, such as C<or_3> or C<and_2>.

=head2 criterion

Return C<condition>.

=head2 shortname

Return C<cond>.

=head2 detail_criterion

Return C<condition>.

=head2 sign_letter

Return C<C>.

=head2 count

Return the number of outcomes. Each subclass must override this, since the
base dies.

=head2 headers

Return the outcome labels as an array reference, in count order. Each
subclass must override this, since the base dies.

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

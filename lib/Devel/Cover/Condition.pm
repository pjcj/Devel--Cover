# Copyright 2001-2011, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Condition;

use strict;
use warnings;

our $VERSION = "0.74";

use base "Devel::Cover::Branch";

sub pad         { $_[0][0][$_] ||= 0 for 0 .. $_[0]->count - 1 }
sub text        { "$_[0][1]{left} $_[0][1]{op} $_[0][1]{right}" }
sub type        { $_[0][1]{type} }
sub count       { require Carp; Carp::confess("count() must be overridden") }
sub headers     { require Carp; Carp::confess("headers() must be overridden") }
sub criterion   { 'condition' }


1

__END__

=head1 NAME

Devel::Cover::Condition - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Condition;

=head1 DESCRIPTION

Module for storing condition coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

=head1 BUGS

Huh?

=head1 VERSION

Version 0.74 - 16th April 2011

=head1 LICENCE

Copyright 2001-2011, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

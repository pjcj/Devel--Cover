# Copyright 2001-2018, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Condition_or_2;

use strict;
use warnings;

# VERSION

use base "Devel::Cover::Condition";

sub count   { 2            }
sub headers { [qw( l !l )] }

1

__END__

=head1 NAME

Devel::Cover::Condition_or_2 - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Condition_or_2;

=head1 DESCRIPTION

Module for storing condition coverage information for or conditions
where the right value is a constant.

=head1 SEE ALSO

 Devel::Cover::Condition

=head1 METHODS

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2001-2018, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

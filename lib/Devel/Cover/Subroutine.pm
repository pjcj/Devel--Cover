# Copyright 2004-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Subroutine;

use strict;
use warnings;

# VERSION

use base "Devel::Cover::Criterion";

sub uncoverable { $_[0][2] }
sub covered     { $_[0][0] }
sub total       { 1 }
sub percentage  { $_[0][0] ? 100 : 0 }
sub error       { $_[0]->simple_error }
sub name        { $_[0][1] }
sub criterion   { "subroutine" }

1

__END__

=head1 NAME

Devel::Cover::Subroutine - Code coverage metrics for Perl subroutines

=head1 SYNOPSIS

 use Devel::Cover::Subroutine;

=head1 DESCRIPTION

Module for storing subroutine coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

=head1 LICENCE

Copyright 2004-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

# Copyright 2001-2010, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Pod;

use strict;
use warnings;

our $VERSION = "0.71";

use base "Devel::Cover::Criterion";

BEGIN { eval "use Pod::Coverage 0.06" }     # We'll use this if it is available.

sub uncoverable { $_[0][2] }
sub covered     { $_[0][0] ? 1 : 0 }
sub total       { 1 }
sub percentage  { $_[0][0] ? 100 : 0 }
sub error       { $_[0][0] xor !$_[0][2] }
sub criterion   { 'pod' }

sub calculate_summary
{
    my $self = shift;
    my ($db, $file) = @_;

    return unless $INC{"Pod/Coverage.pm"};

    my $s = $db->{summary};

    $self->aggregate($s, $file, 'total', $self->total);
    $self->aggregate($s, $file, 'covered', 1)
        if $self->covered;
    $self->aggregate($s, $file, 'error', $self->error);
}

1

__END__

=head1 NAME

Devel::Cover::Pod - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Pod;

=head1 DESCRIPTION

Module for storing pod coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

=head1 BUGS

Huh?

=head1 VERSION

Version 0.71 - 10th September 2010

=head1 LICENCE

Copyright 2001-2010, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

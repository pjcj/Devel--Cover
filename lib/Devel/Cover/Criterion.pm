# Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Criterion;

use strict;
use warnings;

our $VERSION = "0.17";

sub new
{
    my $class = shift;
    my $self  = [];

    bless $self, $class
}

sub coverage    { $_[0][0] }
sub information { $_[0][1] }

sub covered     { "n/a" }
sub total       { "n/a" }
sub percentage  { "n/a" }
sub error       { "n/a" }
sub text        { "n/a" }
sub values      { [ $_[0]->covered ] }

sub calculate_percentage
{
    my $class = shift;
    my ($db, $s) = @_;
    my $covered = $s->{covered} || 0;
    $s->{percentage} = $s->{total} ? $covered * 100 / $s->{total} : 100;
}

1

__END__

=head1 NAME

Devel::Cover::Criterion - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Criterion;

=head1 DESCRIPTION

Abstract base class for all the coverage criteria.

=head1 SEE ALSO

 Devel::Cover

=head1 METHODS

=head2 new

=head1 BUGS

Huh?

=head1 VERSION

Version 0.17 - 15th September 2002

=head1 LICENCE

Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

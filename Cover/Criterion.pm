# Copyright 2001, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Criterion;

use strict;
use warnings;

our $VERSION = "0.13";

sub new
{
    my $class = shift;
    my $self  = [];

    bless $self, $class
}

sub covered    { "n/a" }
sub total      { "n/a" }
sub percentage { "n/a" }
sub error      { "n/a" }

sub calculate_percentage
{
    my $class = shift;
    my ($db, $s) = @_;
    $s->{percentage} = $s->{covered} * 100 / $s->{total};
}

1

__END__

=head1 NAME

Devel::Cover::Criterion - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Criterion;

=head1 DESCRIPTION

This module provides ...

=head1 SEE ALSO

 Devel::Cover

=head1 METHODS

=head2 new

 my $db = Devel::Cover::DB->new(db => "my_coverage_db");

Contructs the DB from the specified database.

=head1 BUGS

Huh?

=head1 VERSION

Version 0.13 - 14th October 2001

=head1 LICENCE

Copyright 2001, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

# Copyright 2001, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Statement;

use strict;
use warnings;

use base "Devel::Cover::Criterion";

our $VERSION = "0.13";

sub covered    { $_[0]->[0] }
sub total      { 1 }
sub percentage { $_[0]->[0] ? 100 : 0 }
sub error      { !$_[0]->[0] }

sub calculate_summary
{
    my $self = shift;
    my ($db, $file) = @_;

    my $s = $db->{summary};

    $s->{$file}{statement}{total}++;
    $s->{$file}{total}{total}++;
    $s->{Total}{statement}{total}++;
    $s->{Total}{total}{total}++;

    if ($self->[0])
    {
        $s->{$file}{statement}{covered}++;
        $s->{$file}{total}{covered}++;
        $s->{Total}{statement}{covered}++;
        $s->{Total}{total}{covered}++;
    }
}

1

__END__

=head1 NAME

Devel::Cover::Statement - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Statement;

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

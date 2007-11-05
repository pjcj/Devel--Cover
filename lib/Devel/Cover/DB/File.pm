# Copyright 2001-2007, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB::File;

use strict;
use warnings;

our $VERSION = "0.62";

use Devel::Cover::Criterion 0.62;

sub calculate_summary
{
    my $self = shift;
    my ($db, $file, $options) = @_;

    my $s = $db->{summary}{$file} ||= {};

    for my $criterion ($self->items)
    {
        next unless $options->{$criterion};
        for my $location ($self->$criterion()->locations)
        {
            for my $cover (@$location)
            {
                $cover->calculate_summary($db, $file);
            }
        }
    }
}

sub calculate_percentage
{
    my $self = shift;
    my ($db, $s) = @_;

    # use Data::Dumper; print STDERR Dumper $s;

    for my $criterion ($self->items)
    {
        next unless exists $s->{$criterion};
        my $c = "Devel::Cover::\u$criterion";
        # print "$c\n";
        $c->calculate_percentage($db, $s->{$criterion});
    }
    Devel::Cover::Criterion->calculate_percentage($db, $s->{total});

    # use Data::Dumper; print STDERR Dumper $s;
}

1

__END__

=head1 NAME

Devel::Cover::DB::File - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::DB::File;

=head1 DESCRIPTION

=head1 SEE ALSO

 Devel::Cover

=head1 METHODS

=head1 BUGS

Huh?

=head1 VERSION

Version 0.62 - 5th November 2007

=head1 LICENCE

Copyright 2001-2007, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

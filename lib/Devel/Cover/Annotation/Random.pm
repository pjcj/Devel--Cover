# Copyright 2004-2005, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Annotation::Random;

use strict;
use warnings;

our $VERSION = "0.52";

use Getopt::Long;

sub new
{
    my $class = shift;
    bless {@_}, $class
}

sub get_options
{
    my ($self, $opt) = @_;
    $self->{count} = 1;
    die "Bad option" unless
        GetOptions($self,
                   qw(
                       count=s
                     ));
}

sub number_of_annotations
{
    my $self = shift;
    $self->{count}
}

sub get_header
{
    my $self = shift;
    my ($annotation) = @_;
    "rand$annotation"
}

sub get_width
{
    my $self = shift;
    my ($annotation) = @_;
    length $self->get_header($self->number_of_annotations)
}

sub get_annotation
{
    my $self = shift;
    my ($line, $annotation) = @_;
    int rand 10
}

sub error
{
    my $self = shift;
    my ($line, $annotation) = @_;
    rand() < 0.2
}

1

__END__

=head1 NAME

Devel::Cover::Annotation::Random - Example annotation for formatters

=head1 SYNOPSIS

 cover -report xxx -annotation random -count 3

=head1 DESCRIPTION

This module provides an example annotation.
It is designed to be called from the C<cover> program.

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 VERSION

Version 0.52 - 13th December 2004

=head1 LICENCE

Copyright 2004-2005, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

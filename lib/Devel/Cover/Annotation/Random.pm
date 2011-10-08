# Copyright 2004-2011, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Annotation::Random;

use strict;
use warnings;

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

sub count
{
    my $self = shift;
    $self->{count}
}

sub header
{
    my $self = shift;
    my ($annotation) = @_;
    "rnd$annotation"
}

sub width
{
    my $self = shift;
    my ($annotation) = @_;
    length $self->header($annotation)
}

sub text
{
    my $self = shift;
    my ($file, $line, $annotation) = @_;
    return "" unless $line;
    $self->{annotation}{$file}[$line][$annotation] = int rand 10
        unless defined $self->{annotation}{$file}[$line][$annotation];
    $self->{annotation}{$file}[$line][$annotation]
}

sub error
{
    my $self = shift;
    my ($file, $line, $annotation) = @_;
    !$self->text($file, $line, $annotation)
}

sub class
{
    my $self = shift;
    my ($file, $line, $annotation) = @_;
    return "" unless $line;
    "c" . int(($self->text($file, $line, $annotation) + 2) / 3)
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

=head1 LICENCE

Copyright 2004-2011, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

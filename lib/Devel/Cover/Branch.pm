# Copyright 2001-2004, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Branch;

use strict;
use warnings;

our $VERSION = "0.50";

use base "Devel::Cover::Criterion";

sub uncoverable { @_ > 1 ? $_[0][2][$_[1]] : scalar grep $_, @{$_[0][2]} }
sub covered     { @_ > 1 ? $_[0][0][$_[1]] : scalar grep $_, @{$_[0][0]} }
sub total       { scalar @{$_[0][0]} }
sub values      { @{$_[0][0]} }
sub text        { $_[0][1]{text} }
sub percentage
{
    my $t = $_[0]->total;
    sprintf "%3d", $t ? $_[0]->covered / $t * 100 : 0
}
sub error
{
    my $self = shift;
    if (@_)
    {
        my $c = shift;
        return !($self->covered($c) xor $self->uncoverable($c));
    }
    my $e = 0;
    for my $c (0 .. $#{$self->[0]})
    {
        $e++ if !($self->covered($c) xor $self->uncoverable($c));
    }
    $e
}

sub calculate_summary
{
    my $self = shift;
    my ($db, $file) = @_;

    my $s = $db->{summary};

    $self->[0] = [0, 0] unless @{$self->[0]};

    my $t = $self->total;
    my $u = $self->uncoverable;
    my $c = $self->covered;
    my $e = $self->error;

    $s->{$file}{branch}{total}       += $t;
    $s->{$file}{total}{total}        += $t;
    $s->{Total}{branch}{total}       += $t;
    $s->{Total}{total}{total}        += $t;

    $s->{$file}{branch}{uncoverable} += $u;
    $s->{$file}{total}{uncoverable}  += $u;
    $s->{Total}{branch}{uncoverable} += $u;
    $s->{Total}{total}{uncoverable}  += $u;

    $s->{$file}{branch}{covered}     += $c;
    $s->{$file}{total}{covered}      += $c;
    $s->{Total}{branch}{covered}     += $c;
    $s->{Total}{total}{covered}      += $c;

    $s->{$file}{branch}{error}       += $e;
    $s->{$file}{total}{error}        += $e;
    $s->{Total}{branch}{error}       += $e;
    $s->{Total}{total}{error}        += $e;
}

1

__END__

=head1 NAME

Devel::Cover::Branch - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Branch;

=head1 DESCRIPTION

Module for storing branch coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

=head1 BUGS

Huh?

=head1 VERSION

Version 0.50 - 25th October 2004

=head1 LICENCE

Copyright 2001-2004, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

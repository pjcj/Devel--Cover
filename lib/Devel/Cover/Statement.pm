# Copyright 2001-2006, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Statement;

use strict;
use warnings;

our $VERSION = "0.55";

use base "Devel::Cover::Criterion";

sub val         { $_[0][0] }
sub uncoverable { $_[0][1] }
sub covered     { $_[0][0] }
sub total       { 1 }
sub percentage  { $_[0][0] ? 100 : 0 }
sub error       { $_[0][0] xor !$_[0][1] }

sub calculate_summary
{
    my $self = shift;
    my ($db, $file) = @_;

    my $s = $db->{summary};

    $s->{$file}{statement}{total}++;
    $s->{$file}{total}{total}++;
    $s->{Total}{statement}{total}++;
    $s->{Total}{total}{total}++;

    if ($self->uncoverable)
    {
        $s->{$file}{statement}{uncoverable}++;
        $s->{$file}{total}{uncoverable}++;
        $s->{Total}{statement}{uncoverable}++;
        $s->{Total}{total}{uncoverable}++;
    }

    if ($self->covered)
    {
        $s->{$file}{statement}{covered}++;
        $s->{$file}{total}{covered}++;
        $s->{Total}{statement}{covered}++;
        $s->{Total}{total}{covered}++;
    }

    if ($self->error)
    {
        $s->{$file}{statement}{error}++;
        $s->{$file}{total}{error}++;
        $s->{Total}{statement}{error}++;
        $s->{Total}{total}{error}++;
    }
}

1

__END__

=head1 NAME

Devel::Cover::Statement - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Statement;

=head1 DESCRIPTION

Module for storing statement coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

=head1 BUGS

Huh?

=head1 VERSION

Version 0.55 - 22nd September 2005

=head1 LICENCE

Copyright 2001-2006, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

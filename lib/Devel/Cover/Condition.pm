# Copyright 2001-2004, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Condition;

use strict;
use warnings;

our $VERSION = "0.51";

use base "Devel::Cover::Branch";

sub pad         { $_[0][0][$_] ||= 0 for 0 .. $_[0]->count - 1 }
sub values      { $_[0]->pad; @{$_[0][0]} }
sub text        { "$_[0][1]{left} $_[0][1]{op} $_[0][1]{right}" }
sub type        { $_[0][1]{type} }
sub count       { require Carp; Carp::confess "count() must be overridden" }
sub headers     { require Carp; Carp::confess "headers() must be overridden" }

sub calculate_summary
{
    my $self = shift;
    my ($db, $file) = @_;

    my $s = $db->{summary};

    $self->pad;

    my $t = $self->total;
    my $u = $self->uncoverable;
    my $c = $self->covered;
    my $e = $self->error;

    $s->{$file}{condition}{total}       += $t;
    $s->{$file}{total}{total}           += $t;
    $s->{Total}{condition}{total}       += $t;
    $s->{Total}{total}{total}           += $t;

    $s->{$file}{condition}{uncoverable} += $u;
    $s->{$file}{total}{uncoverable}     += $u;
    $s->{Total}{condition}{uncoverable} += $u;
    $s->{Total}{total}{uncoverable}     += $u;

    $s->{$file}{condition}{covered}     += $c;
    $s->{$file}{total}{covered}         += $c;
    $s->{Total}{condition}{covered}     += $c;
    $s->{Total}{total}{covered}         += $c;

    $s->{$file}{condition}{error}       += $e;
    $s->{$file}{total}{error}           += $e;
    $s->{Total}{condition}{error}       += $e;
    $s->{Total}{total}{error}           += $e;
}

1

__END__

=head1 NAME

Devel::Cover::Condition - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Condition;

=head1 DESCRIPTION

Module for storing condition coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

=head1 BUGS

Huh?

=head1 VERSION

Version 0.51 - 29th November 2004

=head1 LICENCE

Copyright 2001-2004, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

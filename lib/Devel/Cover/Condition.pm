# Copyright 2001-2004, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Condition;

use strict;
use warnings;

our $VERSION = "0.40";

use base "Devel::Cover::Criterion";

sub covered    { (scalar grep $_, @{$_[0][0]}) }
sub total      { (scalar          @{$_[0][0]}) }
sub percentage
{
    my $t = $_[0]->total;
    sprintf "%3d", $t ? $_[0]->covered / $t * 100 : 0
}
sub error      { scalar grep !$_, @{$_[0][0]} }
sub text       { "$_[0][1]{left} $_[0][1]{op} $_[0][1]{right}" }
sub type       { $_[0][1]{type} }
sub pad        { $_[0][0][$_] ||= 0 for 0 .. $_[0]->count - 1 }
sub values     { $_[0]->pad; @{$_[0][0]} }
sub count      { require Carp; Carp::confess "count() must be overridden" }
sub headers    { require Carp; Carp::confess "headers() must be overridden" }

sub calculate_summary
{
    my $self = shift;
    my ($db, $file) = @_;

    my $s = $db->{summary};

    $self->pad;

    my $t = $self->total;
    my $c = $self->covered;

    $s->{$file}{condition}{total}   += $t;
    $s->{$file}{total}{total}       += $t;
    $s->{Total}{condition}{total}   += $t;
    $s->{Total}{total}{total}       += $t;

    $s->{$file}{condition}{covered} += $c;
    $s->{$file}{total}{covered}     += $c;
    $s->{Total}{condition}{covered} += $c;
    $s->{Total}{total}{covered}     += $c;
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

Version 0.40 - 24th March 2004

=head1 LICENCE

Copyright 2001-2004, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

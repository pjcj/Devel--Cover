# Copyright 2001-2003, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Branch;

use strict;
use warnings;

our $VERSION = "0.21";

use base "Devel::Cover::Criterion";

sub covered    { (scalar grep $_, @{$_[0][0]}) }
sub total      { (scalar          @{$_[0][0]}) }
sub percentage
{
    my $t = $_[0]->total;
    sprintf "%3d", $t ? $_[0]->covered / $t * 100 : 0
}
sub error      { scalar grep !$_, @{$_[0][0]} }
sub text       { $_[0][1]{text} }
sub values     { @{$_[0][0]} }

sub calculate_summary
{
    my $self = shift;
    my ($db, $file) = @_;

    my $s = $db->{summary};

    $self->[0] = [0, 0] unless @{$self->[0]};

    my $t = $self->total;
    my $c = $self->covered;

    $s->{$file}{branch}{total}   += $t;
    $s->{$file}{total}{total}    += $t;
    $s->{Total}{branch}{total}   += $t;
    $s->{Total}{total}{total}    += $t;

    $s->{$file}{branch}{covered} += $c;
    $s->{$file}{total}{covered}  += $c;
    $s->{Total}{branch}{covered} += $c;
    $s->{Total}{total}{covered}  += $c;
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

Version 0.21 - 1st September 2003

=head1 LICENCE

Copyright 2001-2003, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

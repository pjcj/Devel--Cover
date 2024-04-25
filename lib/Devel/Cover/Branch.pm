# Copyright 2001-2024, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Branch;

use strict;
use warnings;

# VERSION

use base "Devel::Cover::Criterion";

sub pad         { my $self = shift; $self->[0] = [0, 0]
                  unless $self->[0] && @{$self->[0]};                    }
sub uncoverable { @_ > 1 ? $_[0][2][$_[1]] : scalar grep $_, @{$_[0][2]} }
sub covered     { @_ > 1 ? $_[0][0][$_[1]] : scalar grep $_, @{$_[0][0]} }
sub total       { scalar @{$_[0][0]}                                     }
sub value       { $_[0][0][$_[1]]                                        }
sub values      { @{$_[0][0]}                                            }
sub text        { $_[0][1]{text}                                         }
sub criterion   { "branch"                                               }

sub percentage {
    my $t = $_[0]->total;
    sprintf "%3d", $t ? $_[0]->covered / $t * 100 : 0
}

sub error {
    my $self = shift;
    if (@_) {
        my $c = shift;
        return $self->err_chk($self->covered($c), $self->uncoverable($c));
    }
    my $e = 0;
    for my $c (0 .. $#{$self->[0]}) {
        $e++ if $self->err_chk($self->covered($c), $self->uncoverable($c));
    }
    $e
}

sub calculate_summary {
    my $self = shift;
    my ($db, $file) = @_;

    my $s = $db->{summary};
    $self->pad;

    $self->aggregate($s, $file, "total",       $self->total      );
    $self->aggregate($s, $file, "uncoverable", $self->uncoverable);
    $self->aggregate($s, $file, "covered",     $self->covered    );
    $self->aggregate($s, $file, "error",       $self->error      );
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

=head1 LICENCE

Copyright 2001-2024, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

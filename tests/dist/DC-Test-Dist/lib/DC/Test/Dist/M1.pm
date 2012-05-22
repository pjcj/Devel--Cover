# Copyright 2012, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package DC::Test::Dist::M1;

use strict;
use warnings;

# VERSION

sub new
{
    bless {}, shift
}

sub m1
{
    my $self = shift;
    if (@_)
    {
        $self->{m1} = shift;
    }
    $self->{m1}
}

sub m2
{
    my $self = shift;
    if (@_)
    {
        $self->{m2} = shift;
    }
    $self->{m2}
}

1

__END__

=head1 NAME

DC::Test::Dist::M1 - Devel::Cover distribution test submodule

=head1 SYNOPSIS

This module is only used as a Devel::Cover test of a complete distribution.

=head1 DESCRIPTION

None.

=head1 LICENCE

Copyright 2012, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

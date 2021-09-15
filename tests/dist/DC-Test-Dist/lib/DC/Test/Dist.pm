# Copyright 2012-2021, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package DC::Test::Dist;

use strict;
use warnings;

# VERSION

use DC::Test::Dist::M1;

sub new {
    bless {}, shift
}

sub d1 {
    my $self = shift;
    if (@_) {
        $self->{d1} = shift;
    }
    $self->{d1}
}

sub d2 {
    my $self = shift;
    if (@_) {
        $self->{d2} = shift;
    }
    $self->{d2}
}

1

__END__

=head1 NAME

DC::Test::Dist - Devel::Cover distribution test module

=head1 SYNOPSIS

This module is only used as a Devel::Cover test of a complete distribution.

=head1 DESCRIPTION

None.

=head1 LICENCE

Copyright 2012-2021, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

# Copyright 2004-2024, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Alias1;

use strict;
use warnings;

use Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw(is_3digits);

sub is_3digits {
    my $val = shift;
    my $retval = undef;
    $retval=1 if $val =~ /^\d{3}$/;
    return $retval;
}

1;

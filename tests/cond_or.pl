#!/usr/bin/perl

# Copyright 2002-2016, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

use strict;
use warnings;

sub cond_dor {
    my ($x) = @_;

    $x->[18] //= undef;
    $x->[18] //= 0;
    $x->[18] //= 0;
    $x->[18] //= 1;
    $x->[18] //= 1;

    $x->[19] //= 1;
    $x->[19] //= 1;
    $x->[19] //= 0;
    $x->[19] //= undef;
    $x->[19] //= 1;

    $x->[20]   = $x->[21] // undef;
    $x->[20]   = $x->[21] // 0;
    $x->[20]   = $x->[21] // 0;
    $x->[20]   = $x->[21] // 1;
    $x->[20]   = $x->[21] // 1;

    $x->[22]   = $x->[22] // undef;
    $x->[22]   = $x->[22] // 0;
    $x->[22]   = $x->[22] // 0;
    $x->[22]   = $x->[22] // 1;
    $x->[22]   = $x->[22] // 1;
}

1;

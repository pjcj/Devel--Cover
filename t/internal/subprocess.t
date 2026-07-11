#!/usr/bin/perl

# Copyright 2011-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Test::More tests => 2;

my $Cmd    = qq[$^X -e "print q(Hello, world.)"];
my $Output = `$Cmd 2>&1`;
is($Output, "Hello, world.", "simple test with perl -e");

$Cmd    = qq[$^X -Mblib -MDevel::Cover=-silent,1 -e "print q(Hello, world.)"];
$Output = `$Cmd 2>&1`;
is($Output, "Hello, world.", "test with perl -MDevel::Cover,-silent,1 -e");

#!/usr/bin/perl

# Copyright 2012, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

require 5.006001;

use strict;
use warnings;

use ExtUtils::MakeMaker;

# VERSION
our $LVERSION = do { eval '$VERSION' || "0.001" };  # for development purposes

$ExtUtils::MakeMaker::Verbose = 0;

WriteMakefile
(
    NAME             => "DC::Test::Dist",
    VERSION          => $LVERSION,
    AUTHOR           => 'Paul Johnson <pjcj@cpan.org>',
    ABSTRACT_FROM    => "lib/DC/Test/Dist.pm",
    clean            => { FILES => "cover_db" },
);

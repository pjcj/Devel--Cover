# Copyright 2002, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Test;

use strict;
use warnings;

our $VERSION = "0.19";

use Carp;

use File::Spec;
use Test;

use Devel::Cover::Inc 0.19;

sub new
{
    my $class = shift;
    my $test  = shift;

    croak "No test specified" unless $test;

    my $coverage = "-coverage statement -coverage branch -coverage condition";

    my $self  =
    {
        test   => $test,
        params =>
        {
          test_parameters  => "-select $test -ignore blib Devel/Cover -merge 0",
          cover_parameters => "$coverage -report text",
        },
        @_
    };

    bless $self, $class;

    $self->get_params
}

sub get_params
{
    my $self = shift;

    my $test = $self->test_file;
    open T, $test or die "Cannot open $test: $!";
    while (<T>)
    {
        $self->{params}{$1} = $2 if /__COVER__\s+(\w+)\s+(.*)/;
    }
    close T or die "Cannot close $test: $!";

    $self
}

sub perl
{
    my $self = shift;

    my $perl = $Devel::Cover::Inc::Perl;
    my $base = $Devel::Cover::Inc::Base;

    $perl .= " -I$base/$_" for "", "blib/lib", "blib/arch";

    $perl
}

sub test_command
{
    my $self = shift;

    my $c = $self->perl;
    unless ($ENV{NOCOVERAGE})
    {
        $c .= " -MDevel::Cover=" .
              join(",", split ' ', $self->{params}{test_parameters})
    }
    $c .= " " . $self->test_file;

    $c
}

sub cover_command
{
    my $self = shift;

    $self->perl .
    " $Devel::Cover::Inc::Base/cover $self->{params}{cover_parameters}"
}

sub test_file
{
    my $self = shift;

    "$Devel::Cover::Inc::Base/tests/$self->{test}"
}

sub cover_gold
{
    my $self = shift;

    "$Devel::Cover::Inc::Base/test_output/cover/$self->{test}"
}

sub run_test
{
    my $self = shift;

    my $debug = $ENV{__COVER__DEBUG} || 0;

    my $gold = $self->cover_gold;
    open I, $gold or die "Cannot open $gold: $!";
    my @cover = <I>;
    close I or die "Cannot close $gold: $!";

    plan tests => scalar @cover;

    my $test_com = $self->test_command;
    print "Running test [$test_com]\n" if $debug;

    open T, "$test_com|" or die "Cannot run $test_com: $!";
    while (<T>)
    {
        print if $debug;
    }
    close T or die "Cannot close $test_com: $!";

    my $cover_com = $self->cover_command;
    print "Running cover [$cover_com]\n" if $debug;

    open T, "$cover_com|" or die "Cannot run $cover_com: $!";
    while (my $t = <T>)
    {
        print $t if $debug;
        my $c = shift @cover || "";
        for ($t, $c)
        {
            s/.* Devel-Cover - \d+ \. \d+ \/*(\S+)\s*/$1/x;
            s/^ \.\.\. .* - \d+ \. \d+ \/*(\S+)\s*/$1/x;
            s/.* Devel \/ Cover \/*(\S+)\s*/$1/x;
            s/copyright .*//ix;
        }
        # print STDERR "[$t]\n[$c]\n" if $t ne $c;
        $ENV{NOCOVERAGE} ? ok 1 : ok $t, $c;
        last if $ENV{NOCOVERAGE} && !@cover;
    }
    if ($ENV{NOCOVERAGE})
    {
        ok 1 for @cover;
    }
    close T or die "Cannot close $cover_com: $!";
}

sub create_gold
{
    my $self = shift;

    my $debug = $ENV{__COVER__DEBUG} || 0;

    my $test_com = $self->test_command;
    print "Running test [$test_com]\n" if $debug;

    system $test_com;
    die "Cannot run $test_com: $?" if $?;

    my $cover_com = $self->cover_command;
    print "Running cover [$cover_com]\n" if $debug;

    my $gold = $self->cover_gold;
    open G, ">$gold" or die "Cannot open $gold: $!";

    open T, "$cover_com|" or die "Cannot run $cover_com: $!";
    while (<T>)
    {
        print;
        print G $_;
    }
    close T or die "Cannot close $cover_com: $!";

    close G or die "Cannot close $gold: $!";
}

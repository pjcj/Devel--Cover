# Copyright 2002-2003, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Test;

use strict;
use warnings;

our $VERSION = "0.24";

use Carp;

use File::Spec;
use Test;

use Devel::Cover::Inc 0.24;

sub new
{
    my $class = shift;
    my $test  = shift;

    croak "No test specified" unless $test;

    my %params = @_;

    my $criteria = delete $params{criteria} ||
                   "statement branch condition subroutine";

    my $self  =
    {
        test     => $test,
        criteria => $criteria,
        %params
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
        $self->{$1} = $2 if /__COVER__\s+(\w+)\s+(.*)/;
    }
    close T or die "Cannot close $test: $!";

    $self->{test_parameters}  = "-select $self->{test} -ignore blib Devel/Cover"
                              . " -merge 0 -coverage $self->{criteria}";
    $self->{cover_parameters} = join(" ", map "-coverage $_", split " ", $self->{criteria})
                              . " -report text";

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
              join(",", split ' ', $self->{test_parameters})
    }
    $c .= " " . $self->test_file;

    $c
}

sub cover_command
{
    my $self = shift;

    $self->perl . " $Devel::Cover::Inc::Base/cover $self->{cover_parameters}"
}

sub test_file
{
    my $self = shift;

    "$Devel::Cover::Inc::Base/tests/$self->{test}"
}

sub cover_gold
{
    my $self = shift;

    my $latest_tested = 5.008001;
    my $v = $] > $latest_tested ? $latest_tested : $];

    $v = $ENV{__COVER_GOLDEN_VERSION} if exists $ENV{__COVER_GOLDEN_VERSION};

    "$Devel::Cover::Inc::Base/test_output/cover/$self->{test}.$v"
}

sub run_test
{
    my $self = shift;

    my $debug = $ENV{__COVER__DEBUG} || 0;

    my $gold = $self->cover_gold;
    open I, $gold or die "Cannot open $gold: $!";
    my @cover = <I>;
    close I or die "Cannot close $gold: $!";

    eval "use Test::Differences";
    my $differences = $INC{"Test/Differences.pm"};

    my $skip = "";
    if ($self->{criteria} =~ /\bpod\b/)
    {
        eval "use Pod::Coverage";
        $skip .= $INC{"Pod/Coverage.pm"} ? "" : "Pod::Coverage unavailable";
    }

    plan tests => ($differences || $skip) ? 1 : scalar @cover;

    if ($skip)
    {
        skip($skip, 1);
        return;
    }

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

    my @at;
    my @ac;

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
        if ($differences)
        {
            push @at, $t;
            push @ac, $c;
        }
        else
        {
            $ENV{NOCOVERAGE} ? ok 1 : ok $t, $c;
            last if $ENV{NOCOVERAGE} && !@cover;
        }
    }
    if ($differences)
    {
        $ENV{NOCOVERAGE} ? ok 1 : eq_or_diff(\@at, \@ac);
    }
    elsif ($ENV{NOCOVERAGE})
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

# Copyright 2002-2004, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Test;

use strict;
use warnings;

our $VERSION = "0.42";

use Carp;

use File::Spec;
use Test;

use Devel::Cover::Inc 0.42;

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
        test      => $test,
        criteria  => $criteria,
        skip      => "",
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
    $self->{skip}             = $self->{skip_reason}
        if exists $self->{skip_test} && eval $self->{skip_test};

    $self
}

sub perl
{
    my $self = shift;

    my $perl = $Devel::Cover::Inc::Perl;
    my $base = $Devel::Cover::Inc::Base;

    $perl =~ s/ /\\ /g;
    $base =~ s/ /\\ /g;

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
    my $t = $self->test_file;
    $t =~ s/ /\\ /g;
    $c .= " $t";

    $c
}

sub cover_command
{
    my $self = shift;

    my $b = $Devel::Cover::Inc::Base;
    $b =~ s/ /\\ /g;
    $self->perl . " $b/cover $self->{cover_parameters}"
}

sub test_file
{
    my $self = shift;

    "$Devel::Cover::Inc::Base/tests/$self->{test}"
}

sub cover_gold
{
    my $self = shift;

    my $test = $self->{golden_test} || $self->{test};

    my $td = "$Devel::Cover::Inc::Base/test_output/cover";
    opendir D, $td or die "Can't opendir $td: $!";
    my @versions = sort    { $a <=> $b }
                   map     { /^$test\.(5\.\d+)$/ ? $1 : () }
                   readdir D;
    closedir D or die "Can't closedir $td: $!";

    my $v = "5.0";
    for (@versions)
    {
        last if $_ > $];
        $v = $_;
    }

    die "Can't find golden results for $test" unless $v;

    $v = $ENV{__COVER_GOLDEN_VERSION} if exists $ENV{__COVER_GOLDEN_VERSION};

    "$td/$test.$v"
}

sub run_command
{
    my $self = shift;
    my ($command) = @_;

    my $debug = $ENV{__COVER__DEBUG} || 0;

    print "Running test [$command]\n" if $debug;

    open T, "$command 2>&1 |" or die "Cannot run $command: $!";
    while (<T>)
    {
        print if $debug;
    }
    close T or die "Cannot close $command: $!";
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

    my $skip = $self->{skip};
    if (!$skip && $self->{criteria} =~ /\bpod\b/)
    {
        eval "use Pod::Coverage";
        $skip = $INC{"Pod/Coverage.pm"} ? "" : "Pod::Coverage unavailable";
    }

    plan tests => ($differences || $skip) ? 1 : scalar @cover;

    if ($skip)
    {
        skip($skip, 1);
        return;
    }

    if ($self->{run_test})
    {
        $self->{run_test}->($self)
    }
    else
    {
        $self->run_command($self->test_command);
    }

    my $cover_com = $self->cover_command;
    print "Running cover [$cover_com]\n" if $debug;

    my @at;
    my @ac;

    open T, "$cover_com 2>&1 |" or die "Cannot run $cover_com: $!";
    while (my $t = <T>)
    {
        print $t if $debug;
        next if $t =~ /^Devel::Cover: merging run/;
        my $c = shift @cover || "";
        for ($t, $c)
        {
            s/^(Reading database from ).*/$1/;
            s|(__ANON__\[) .* (/tests/ \w+ : \d+ \])|$1$2|x;
            s/(Subroutine) +(Location)/$1 $2/;
            s/-+/-/;
            # s/.* Devel-Cover - \d+ \. \d+ \/*(\S+)\s*/$1/x;
            s/^ \.\.\. .* - \d+ \. \d+ \/*(\S+)\s*/$1/x;
            s/.* Devel \/ Cover \/*(\S+)\s*/$1/x;
            s/^(Devel::Cover: merging run).*/$1/;
            s/copyright .*//ix;
            no warnings "exiting";
            eval $self->{changes} if exists $self->{changes};
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

    # Pod::Coverage not available on all versions, but it must be there on 5.6.1
    return if $self->{criteria} =~ /\bpod\b/ && $] != 5.006001;

    my $debug = $ENV{__COVER__DEBUG} || 0;

    my $test_com = $self->test_command;
    print "Running test [$test_com]\n" if $debug;

    system $test_com;
    die "Cannot run $test_com: $?" if $?;

    my $cover_com = $self->cover_command;
    print "Running cover [$cover_com]\n" if $debug;

    my $gold = $self->cover_gold;
    my $new_gold = $gold;
    $new_gold =~ s/(5\.\d+)$/$]/;
    my $gv = $1;
    my $ng = "";

    open G, ">$new_gold" or die "Cannot open $new_gold: $!";

    open T, "$cover_com|" or die "Cannot run $cover_com: $!";
    while (<T>)
    {
        next if /^Devel::Cover: merging run/;
        # print;
        print G $_;
        $ng .= $_;
    }
    close T or die "Cannot close $cover_com: $!";

    close G or die "Cannot close $new_gold: $!";

    return if $gv eq "5.0" || $gv eq $];

    open G, "$gold" or die "Cannot open $gold: $!";
    my $g = do { local $/; <G> };
    close G or die "Cannot close $gold: $!";

    if ($ng eq $g)
    {
        print "Output from $new_gold matches $gold\n";
        unlink $new_gold;
    }
}

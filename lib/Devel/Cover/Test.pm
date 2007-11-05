# Copyright 2002-2007, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Test;

use strict;
use warnings;

our $VERSION = "0.62";

use Carp;

use File::Spec;
use Test;

use Devel::Cover::Inc 0.62;

my $Test;

sub new
{
    my $class = shift;
    my $test  = shift;

    croak "No test specified" unless $test;

    my %params = @_;

    my $criteria = delete $params{criteria} ||
                   "statement branch condition subroutine";

    my $self =
    {
        test             => $test,
        criteria         => $criteria,
        skip             => "",
        uncoverable_file => "",
        select           => "",
        ignore           => "",
        run_test_at_end  => 1,
        %params
    };

    $Test = bless $self, $class;

    $self->get_params
}

sub get_params
{
    my $self = shift;

    my $test = $self->test_file;
    if (open T, $test)
    {
        while (<T>)
        {
            $self->{$1} = $2 if /__COVER__\s+(\w+)\s+(.*)/;
        }
        close T or die "Cannot close $test: $!";
    }

    $self->{select}         ||= "-select $self->{test}";
    $self->{test_parameters}  = "$self->{select}"
                              . " -ignore blib Devel/Cover $self->{ignore}"
                              . " -merge 0 -coverage $self->{criteria} "
                              . ($self->{test_parameters} || "");
    $self->{criteria} =~ s/-\w+//g;
    $self->{cover_parameters} = join(" ", map "-coverage $_",
                                              split " ", $self->{criteria})
                              . " -report text";
    $self->{cover_parameters} .= " -uncoverable_file $self->{uncoverable_file}"
        if $self->{uncoverable_file};
    $self->{skip}             = $self->{skip_reason}
        if exists $self->{skip_test} && eval "{$self->{skip_test}}";

    $self
}

sub test { $Test }

sub shell_quote
{
    my ($item) = @_;
    # properly quote the item
    $^O eq "MSWin32" ? (/ / and $_ = qq("$_")) : s/ /\\ /g for $item;
    $item
};

sub perl
{
    my $self = shift;

    my $perl = shell_quote $Devel::Cover::Inc::Perl;
    my $base = $Devel::Cover::Inc::Base;

    $perl .= " " . shell_quote "-I$base/$_" for "", "blib/lib", "blib/arch";

    $perl
}

sub test_command
{
    my $self = shift;

    my $c = $self->perl;
    unless ($ENV{DEVEL_COVER_NO_COVERAGE})
    {
        $c .= " -MDevel::Cover=" .
              join(",", split ' ', $self->{test_parameters})
    }
    $c .= " " . shell_quote $self->test_file;
    $c .= " " . $self->test_file_parameters;

    $c
}

sub cover_command
{
    my $self = shift;

    my $b = shell_quote $Devel::Cover::Inc::Base;
    my $c = $self->perl . " $b/cover $self->{cover_parameters}";
    $c
}

sub test_file
{
    my $self = shift;

    "$Devel::Cover::Inc::Base/tests/$self->{test}"
}

sub test_file_parameters
{
    my $self = shift;

    exists $self->{test_file_parameters} ? $self->{test_file_parameters} : ""
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

    # die "Can't find golden results for $test" if $v eq "5.0";

    $v = $ENV{DEVEL_COVER_GOLDEN_VERSION}
        if exists $ENV{DEVEL_COVER_GOLDEN_VERSION};

    "$td/$test.$v"
}

sub run_command
{
    my $self = shift;
    my ($command) = @_;

    my $debug = $ENV{DEVEL_COVER_DEBUG} || 0;

    print STDERR "Running test [$command]\n" if $debug;

    open T, "$command 2>&1 |" or die "Cannot run $command: $!";
    while (<T>)
    {
        print STDERR if $debug;
    }
    close T or die "Cannot close $command: $!";

    1
}

sub run_test
{
    my $self = shift;

    $self->{run_test_at_end} = 0;

    my $debug = $ENV{DEVEL_COVER_DEBUG} || 0;

    my $gold = $self->cover_gold;
    open I, $gold or die "Cannot open $gold: $!";
    my @cover = <I>;
    close I or die "Cannot close $gold: $!";
    $self->{cover} = \@cover;

    # print STDERR "gold from $gold\n", @cover if $debug;

    eval "use Test::Differences";
    my $differences = $INC{"Test/Differences.pm"};

    plan tests => ($differences || $self->{skip})
                  ? 1
                  : exists $self->{tests}
                    ? $self->{tests}->(scalar @cover)
                    : scalar @cover;

    if ($self->{skip})
    {
        skip($self->{skip}, 1);
        return;
    }

    $self->{run_test}
        ? $self->{run_test}->($self)
        : $self->run_command($self->test_command);

    $self->run_cover unless $self->{no_report};

    $self->{end}->() if $self->{end};
}

sub run_cover
{
    my $self = shift;

    my $debug = $ENV{DEVEL_COVER_DEBUG} || 0;
    eval "use Test::Differences";
    my $differences = $INC{"Test/Differences.pm"};

    my $cover_com = $self->cover_command;
    print STDERR "Running cover [$cover_com]\n" if $debug;

    my @at;
    my @ac;

    my $change_line = sub
    {
        my ($get_line) = @_;
        local *_;
        LOOP:
        while (1)
        {
            $_ = scalar $get_line->();
            $_ = "" unless defined $_;
            print STDERR $_ if $debug;
            redo if /^Devel::Cover: merging run/;
            redo if /^Set up gcc environment/;  # for MinGW
            s/^(Reading database from ).*/$1/;
            s|(__ANON__\[) .* (/tests/ \w+ : \d+ \])|$1$2|x;
            s/(Subroutine) +(Location)/$1 $2/;
            s/-+/-/;
            # s/.* Devel-Cover - \d+ \. \d+ \/*(\S+)\s*/$1/x;
            s/^ \.\.\. .* - \d+ \. \d+ \/*(\S+)\s*/$1/x;
            s/.* Devel \/ Cover \/*(\S+)\s*/$1/x;
            s/^(Devel::Cover: merging run).*/$1/;
            s/^(Run: ).*/$1/;
            s/^(OS: ).*/$1/;
            s/^(Perl version: ).*/$1/;
            s/^(Start: ).*/$1/;
            s/^(Finish: ).*/$1/;
            s/copyright .*//ix;
            no warnings "exiting";
            eval $self->{changes} if exists $self->{changes};
            return $_;
        }
    };

    open T, "$cover_com 2>&1 |" or die "Cannot run $cover_com: $!";
    while (!eof T)
    {
        my $t = $change_line->(sub { <T> });
        my $c = $change_line->(sub { shift @{$self->{cover}} });
        # print STDERR "[$t]\n[$c]\n" if $t ne $c;
        # chomp(my $tn = $t); chomp(my $cn = $c);
        # print STDERR "c-[$tn] $.\ng=[$cn]\n";
        if ($differences)
        {
            push @at, $t;
            push @ac, $c;
        }
        else
        {
            $ENV{DEVEL_COVER_NO_COVERAGE} ? ok 1 : ok $t, $c;
            last if $ENV{DEVEL_COVER_NO_COVERAGE} && !@{$self->{cover}};
        }
    }
    if ($differences)
    {
        no warnings "redefine";
        local *Test::_quote = sub { "@_" };
        $ENV{DEVEL_COVER_NO_COVERAGE} ? ok 1 : eq_or_diff(\@at, \@ac, "output");
    }
    elsif ($ENV{DEVEL_COVER_NO_COVERAGE})
    {
        ok 1 for @{$self->{cover}};
    }
    close T or die "Cannot close $cover_com: $!";
}

sub create_gold
{
    my $self = shift;

    $self->{run_test_at_end} = 0;

    # Pod::Coverage not available on all versions, but it must be there on
    # 5.6.1 and 5.8.0
    return if $self->{criteria} =~ /\bpod\b/ &&
               $] != 5.006001 &&
               $] != 5.008000;

    my $debug = $ENV{DEVEL_COVER_DEBUG} || 0;

    my $gold = $self->cover_gold;
    my $new_gold = $gold;
    $new_gold =~ s/(5\.\d+)$/$]/;
    my $gv = $1;
    my $ng = "";

    unless (-e $new_gold)
    {
        open my $g, ">$new_gold" or die "Can't open $new_gold: $!";
    }

    $self->{run_test}
        ? $self->{run_test}->($self)
        : $self->run_command($self->test_command);

    my $cover_com = $self->cover_command;
    print STDERR "Running cover [$cover_com]\n" if $debug;

    open G, ">$new_gold" or die "Cannot open $new_gold: $!";
    open T, "$cover_com 2>&1 |" or die "Cannot run $cover_com: $!";
    while (my $l = <T>)
    {
        next if $l =~ /^Devel::Cover: merging run/;
        $l =~ s/^($_: ).*$/$1.../
            for "Run", "Perl version", "OS", "Start", "Finish";
        print STDERR $l if $debug;
        print G $l;
        $ng .= $l;
    }
    close T or die "Cannot close $cover_com: $!";
    close G or die "Cannot close $new_gold: $!";

    unless ($gv eq "5.0" || $gv eq $])
    {
        open G, "$gold" or die "Cannot open $gold: $!";
        my $g = do { local $/; <G> };
        close G or die "Cannot close $gold: $!";

        # print STDERR "checking $new_gold against $gold\n";
        if ($ng eq $g)
        {
            print "Output from $new_gold matches $gold\n";
            unlink $new_gold;
        }
    }

    $self->{end}->() if $self->{end};
}

END
{
    my $self = $Test;
    $self->run_test if $self->{run_test_at_end};
}

1;

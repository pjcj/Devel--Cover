# Copyright 2001, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Process;

use strict;
use warnings;

use Carp;

our $VERSION = "0.02";

sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self =
    {
        criteria       => [ qw( statement branch path condition ) ],
        criteria_short => [ qw( stmt      branch path cond      ) ],
        @_
    };
    $self->{all_criteria}       = [ @{$self->{criteria}},       "total" ];
    $self->{all_criteria_short} = [ @{$self->{criteria_short}}, "total" ];

    bless $self, $class;

    if (defined $self->{file})
    {
        open F, "<$self->{file}" or croak "Unable to open $self->{file}: $!";
        $self->{filehandle} = *F{IO};
    }

    if (defined $self->{filehandle})
    {
        $self->read;
    }

    if (defined $self->{file})
    {
        close F or croak "Unable to close $self->{file}: $!";
    }

    croak "No input file, filehandle or cover" unless defined $self->{cover};

    $self
}


sub read
{
    my $self = shift;
    local $/;
    my $cover;
    my $fh = $self->{filehandle};
    eval <$fh>;
    croak $@ if $@;
    $self->{cover} = $cover
}


sub cover
{
    my $self = shift;
    $self->{cover}
}

sub calculate_summary
{
    my $self = shift;
    my ($force) = @_;
    return if defined $self->{summary} && !$force;
    $self->{summary} = {};
    my $statements = 0;
    my $statements_covered = 0;
    for my $file (sort keys %{$self->{cover}})
    {
        my $lines = $self->{cover}{$file};
        for my $line (sort { $a <=> $b } keys %$lines)
        {
            my $l = $lines->{$line};
            $statements         += @$l;
            $statements_covered += map { $_ || () } @$l;
        }
        $self->{summary}{$file}{statement}{total}    = $statements;
        $self->{summary}{$file}{statement}{covered}  = $statements_covered;
        $self->{summary}{$file}{total}{total}       += $statements;
        $self->{summary}{$file}{total}{covered}     += $statements_covered;
        $self->{summary}{Total}{statement}{total}   += $statements;
        $self->{summary}{Total}{statement}{covered} += $statements_covered;
        $self->{summary}{Total}{total}{total}       += $statements;
        $self->{summary}{Total}{total}{covered}     += $statements_covered;
    }
}

sub print_summary
{
    my $self = shift;
    $self->calculate_summary;

    my $format = sub
    {
        my ($part, $critrion) = @_;
        exists $part->{$critrion}
            ? $part->{$critrion}{total}
                  ? sprintf "%6.2f", $part->{$critrion}{covered} * 100 /
                                     $part->{$critrion}{total}
                  : "-"
            : "n/a"

    };

    my $fmt = "%-42s %6s %6s %6s %6s %6s\n";
    printf $fmt, "-" x 42, ("------") x 5;
    printf $fmt, "File", @{$self->{all_criteria_short}};
    printf $fmt, "-" x 42, ("------") x 5;

    my $s = $self->{summary};
    for my $file (grep($_ ne "Total", sort keys %$s), "Total")
    {
        printf $fmt,
               $file,
               map { $format->($s->{$file}, $_) } @{$self->{all_criteria}};

    }

    printf $fmt, "-" x 42, ("------") x 5;
}

sub print_details
{
    my $self = shift;
    for my $file (sort keys %{$self->{cover}})
    {
        print "$file\n\n";
        my $lines = $self->{cover}{$file};
        for my $line (sort { $a <=> $b } keys %$lines)
        {
            my $l = $lines->{$line};
            printf "%4d: " . ("%6d" x @$l) . "\n", $line, @$l;
        }
        print "\n";
    }
}

1

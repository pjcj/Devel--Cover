# Copyright 2001, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Process;

use strict;
use warnings;

use Carp;

our $VERSION = "0.04";

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
    my $s = $self->{summary} = {};

    my $cover = $self->{cover};
    my ($t, $c, $lines);
    for my $file (sort keys %$cover)
    {
        $t = $c = 0;
        $lines = $cover->{$file}{statement};
        for my $line (sort { $a <=> $b } keys %$lines)
        {
            my $l = $lines->{$line};
            $t += @$l;
            $c += grep { $_ } @$l;
        }
        $s->{$file}{statement}{total}    = $t;
        $s->{$file}{statement}{covered}  = $c;
        $s->{$file}{total}{total}       += $t;
        $s->{$file}{total}{covered}     += $c;
        $s->{Total}{statement}{total}   += $t;
        $s->{Total}{statement}{covered} += $c;
        $s->{Total}{total}{total}       += $t;
        $s->{Total}{total}{covered}     += $c;

        $t = $c = 0;
        $lines = $cover->{$file}{condition};
        for my $line (sort { $a <=> $b } keys %$lines)
        {
            my $l = $lines->{$line};
            $t += @$l;
            $c += grep { !grep { !$_ } @$_ } @$l;
        }
        $s->{$file}{condition}{total}    = $t;
        $s->{$file}{condition}{covered}  = $c;
        $s->{$file}{total}{total}       += $t;
        $s->{$file}{total}{covered}     += $c;
        $s->{Total}{condition}{total}   += $t;
        $s->{Total}{condition}{covered} += $c;
        $s->{Total}{total}{total}       += $t;
        $s->{Total}{total}{covered}     += $c;
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
            ? sprintf "%6.2f", $part->{$critrion}{total}
                  ? $part->{$critrion}{covered} * 100 /
                    $part->{$critrion}{total}
                  : 100
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
    print "\n\n";
}

sub print_details
{
    my $self = shift;
    my (@files) = @_;
    @files = sort keys %{$self->{cover}} unless @files;
    for my $file (@files)
    {
        print "$file\n\n";
        my $lines = $self->{cover}{$file}{statement};
        my $fmt = "%-5d: %6s %s\n";

        open F, $file or croak "Unable to open $file: $!";

        while (<F>)
        {
            if (exists $lines->{$.})
            {
                my @c = @{$lines->{$.}};
                printf "%5d: %6d %s", $., shift @c, $_;
                printf "     : %6d\n", shift @c while @c;
            }
            else
            {
                printf "%5d:        %s", $., $_;
            }
        }

        close F or croak "Unable to close $file: $!";
        print "\n\n";
    }
}

1

# Copyright 2001, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB;

use strict;
use warnings;

use Carp;
use Data::Dumper;
use File::Path;

our $VERSION = "0.06";

my $DB = "cover.1";  # Version 1 of the database.

sub new
{
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self =
    {
        criteria       => [ qw( statement branch path condition ) ],
        criteria_short => [ qw( stmt      branch path cond      ) ],
        indent         => 1,
        cover          => {},
        @_
    };
    $self->{all_criteria}       = [ @{$self->{criteria}},       "total" ];
    $self->{all_criteria_short} = [ @{$self->{criteria_short}}, "total" ];

    bless $self, $class;

    my $file;
    if (defined $self->{db})
    {
        $self->validate_db;
        $file = "$self->{db}/$DB";
        open F, "<$file" or croak "Unable to open $file: $!";
        $self->{filehandle} = *F{IO};
    }

    $self->read if defined $self->{filehandle};

    if (defined $file)
    {
        close F or croak "Unable to close $file: $!";
    }

    croak "No input db, filehandle or cover" unless defined $self->{cover};

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
    $self->{cover} = $cover;
    $self
}

sub write
{
    my $self = shift;
    $self->{db} = shift if @_;
    croak "No db specified" unless length $self->{db};
    $self->validate_db;
    local $Data::Dumper::Indent = $self->indent;
    my $file = "$self->{db}/$DB";
    open OUT, ">$file" or croak "Cannot open $file\n";
    print OUT Data::Dumper->Dump([$self->{cover}], ["cover"]);
    close OUT or croak "Cannot close $file\n";
    $self
}

sub delete
{
    my $self = shift;
    $self->{db} = shift if @_;
    croak "No db specified" unless length $self->{db};
    rmtree($self->{db});
    $self
}

sub cover
{
    my $self = shift;
    $self->{cover}
}

sub validate_db
{
    my $self = shift;
    unless (-d $self->{db})
    {
        mkdir $self->{db}, 0777 or croak "Cannot mkdir $self->{db}: $!\n";
    }
    $self
}

sub indent
{
    my $self = shift;
    $self->{indent} = shift if @_;
    $self->{indent}
}

sub merge
{
    my ($self, $from) = @_;
    _merge_hash($self->cover, $from->cover);
    $self
}

sub _merge_hash
{
    my ($into, $from) = @_;
    for my $fkey (keys %{$from})
    {
        my $fval = $from->{$fkey};
        my $fval_ref = ref $fval;

        if (defined $into->{$fkey} and UNIVERSAL::isa($into->{$fkey}, "ARRAY"))
        {
            _merge_array($into->{$fkey}, $fval);
        }
        elsif (defined $fval && UNIVERSAL::isa($fval, "HASH"))
        {
            if (defined $into->{$fkey} and
                UNIVERSAL::isa($into->{$fkey}, "HASH"))
            {
                _merge_hash($into->{$fkey}, $fval);
            }
            else
            {
                $into->{$fkey} = $fval;
            }
        }
        else
        {
            # A scalar (or a blessed scalar).  We know there is no into
            # array, or we would just have merged with it.

            $into->{$fkey} = $fval;
        }
    }
}

sub _merge_array
{
    my ($into, $from) = @_;
    for my $i (@$into)
    {
        my $f = shift @$from;
        if (UNIVERSAL::isa($i, "ARRAY"))
        {
            _merge_array($i, $f);
        }
        else
        {
            $i += $f;
        }
    }
    push @$into, @$from;
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

sub trimmed_file
{
    my ($f, $len) = @_;
    substr $f, 0, 3 - $len, "..." if length $f > $len;
    $f
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
               trimmed_file($file, 42),
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

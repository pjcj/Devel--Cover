# Copyright 2001-2004, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB;

use strict;
use warnings;

our $VERSION = "0.39";

use Devel::Cover::Criterion     0.39;
use Devel::Cover::DB::File      0.39;
use Devel::Cover::DB::Structure 0.39;

use Carp;
use File::Path;
use Storable;

my $DB = "cover.10";  # Version 10 of the database.

sub new
{
    my $class = shift;
    my $self  =
    {
        criteria       =>
            [ qw( statement branch path condition subroutine pod time ) ],
        criteria_short =>
            [ qw( stmt      branch path cond      sub        pod time ) ],
        runs           => {},
        collected      => {},
        @_
    };

    $self->{all_criteria}       = [ @{$self->{criteria}},       "total" ];
    $self->{all_criteria_short} = [ @{$self->{criteria_short}}, "total" ];
    $self->{base} ||= $self->{db};
    bless $self, $class;

    my $file;
    if (defined $self->{db})
    {
        $self->validate_db;
        $file = "$self->{db}/$DB";
        $self->read($file) if -e $file;
        return $self unless -e $file;
    }

    # croak "No input db, filehandle or cover" unless defined $self->{cover};

    $self
}

sub     criteria       { @{$_[0]->{    criteria      }} }
sub     criteria_short { @{$_[0]->{    criteria_short}} }
sub all_criteria       { @{$_[0]->{all_criteria      }} }
sub all_criteria_short { @{$_[0]->{all_criteria_short}} }

sub read
{
    my $self = shift;
    my $file = shift;
    my $db   = retrieve($file);
    $self->{runs} = $db->{runs};
    $self
}

sub write
{
    my $self = shift;
    $self->{db} = shift if @_;
    croak "No db specified" unless length $self->{db};
    unless (-d $self->{db})
    {
        mkdir $self->{db}, 0777 or croak "Cannot mkdir $self->{db}: $!\n";
    }
    $self->validate_db;

    my $db =
    {
        runs  => $self->{runs},
    };

    Storable::nstore($db, "$self->{db}/$DB");

    $self->{structure}->write($self->{base}) if $self->{structure};

    $self
}

sub delete
{
    my $self = shift;
    my $db = "";
    $db = $self->{db} if ref $self;
    $db = shift if @_;
    $self->{db} = $db if ref $self;
    croak "No db specified" unless length $db;
    opendir DIR, $db or die "Can't opendir $db: $!";
    my @files = map "$db/$_", map /(.*)/ && $1, grep !/^\.\.?/, readdir DIR;
    closedir DIR or die "Can't closedir $db/runs: $!";
    rmtree(\@files);
    $self
}

sub merge_runs
{
    my $self = shift;
    my $db = $self->{db};
    # print "merge_runs from $db/runs/*\n";
    return $self unless length $db;
    opendir DIR, "$db/runs" or return $self;
    my @runs = map "$db/runs/$_", grep !/^\.\.?/, readdir DIR;
    closedir DIR or die "Can't closedir $db/runs: $!";

    # The ordering is important here.  The runs need to be merged in the order
    # they were created.  We're only at a granularity of one second, but that
    # shouldn't be a problem unless a file is altered and the coverage run
    # created in less than a second.  I think we're OK for now.

    for my $run (sort @runs)
    {
        print STDERR "Devel::Cover: merging run $run <$self->{base}>\n"
            unless $Devel::Cover::Silent;
        my $r = Devel::Cover::DB->new(base => $self->{base}, db => $run);
        rmtree($run);
        $self->merge($r);
    }
    $self->write($db) if @runs;
    $self
}

sub validate_db
{
    my $self = shift;
    $self
}

sub is_valid
{
    my $self = shift;
    -e "$self->{db}/$DB"
}

sub collected
{
    my $self = shift;
    $self->cover;
    sort keys %{$self->{collected}}
}

sub merge
{
    my ($self, $from) = @_;

    # use Data::Dumper; print "Merging ", Dumper($self), "From ", Dumper($from);

    while (my ($fname, $frun) = each %{$from->{runs}})
    {
        while (my ($file, $digest) = each %{$frun->{digest}})
        {
            while (my ($name, $run) = each %{$self->{runs}})
            {
                if (exists $run->{digest}{$file} &&
                    $run->{digest}{$file} ne $digest)
                {
                    # File has changed.  Delete old coverage instead of merging.
                    print STDERR "Devel::Cover: Deleting old coverage for ",
                                               "changed file $file\n"
                        unless $Devel::Cover::Silent;
                    delete $run->{digest}{$file};
                    delete $run->{count} {$file};
                    delete $run->{vec}   {$file};
                }
            }
        }
    }

    # When the database gets big, it's quicker to merge into what's
    # already there.

    _merge_hash($from->{runs},      $self->{runs});
    _merge_hash($from->{collected}, $self->{collected});

    $_[0] = $from;
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
            # array, or we would have just merged with it.

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
        if (UNIVERSAL::isa($i, "ARRAY") ||
            !defined $i && UNIVERSAL::isa($f, "ARRAY"))
        {
            _merge_array($i, $f || []);
        }
        elsif (UNIVERSAL::isa($i, "HASH") ||
              !defined $i && UNIVERSAL::isa($f, "HASH") )
        {
            _merge_hash($i, $f || {});
        }
        elsif (UNIVERSAL::isa($i, "SCALAR") ||
              !defined $i && UNIVERSAL::isa($f, "SCALAR") )
        {
            $$i += $$f;
        }
        else
        {
            if (defined $f)
            {
                $i ||= 0;
                if ($f =~ /^\d+$/ && $i =~ /^\d+$/)
                {
                    $i += $f;
                }
                elsif ($i ne $f)
                {
                    warn "<$i> does not match <$f> - using later value";
                    $i = $f;
                }
            }
        }
    }
    push @$into, @$from;
}

sub summary
{
    my $self = shift;
    my ($file, $criteriion, $part) = @_;
    my $f = $self->{summary}{$file};
    return $f unless $f && defined $criteriion;
    my $c = $f->{$criteriion};
    $c && defined $part ? $c->{$part} : $c
}

sub calculate_summary
{
    my $self = shift;
    my %options = @_;

    return if exists $self->{summary} > 0 && !$options{force};
    my $s = $self->{summary} = {};

    for my $file ($self->cover->items)
    {
        $self->cover->get($file)->calculate_summary($self, $file, \%options);
        $self->cover->get($file)->calculate_percentage($self, $s->{$file});
    }

    my $t = $self->{summary}{Total};
    for my $criterion ($self->criteria)
    {
        next unless exists $t->{$criterion};
        my $c = "Devel::Cover::\u$criterion";
        $c->calculate_percentage($self, $t->{$criterion});
    }
    Devel::Cover::Criterion->calculate_percentage($self, $t->{total});
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

    my %options = map(($_ => 1), @_ ? @_ : $self->collected);
    $options{total} = 1 if keys %options;

    my $n = keys %options;

    my $oldfh = select STDOUT;

    $self->calculate_summary(%options);

    my $format = sub
    {
        my ($part, $criterion) = @_;
        $options{$criterion} && exists $part->{$criterion}
            ? sprintf "%4.1f", $part->{$criterion}{percentage}
            : "n/a"
    };

    my $fw = 77 - $n * 7;
    $fw = 28 if $fw < 28;

    my $fmt = "%-${fw}s" . " %6s" x $n . "\n";
    printf $fmt, "-" x $fw, ("------") x $n;
    printf $fmt, "File",
                 map { $self->{all_criteria_short}[$_] }
                 grep { $options{$self->{all_criteria}[$_]} }
                 (0 .. $#{$self->{all_criteria}});
    printf $fmt, "-" x $fw, ("------") x $n;

    my $s = $self->{summary};
    for my $file (grep($_ ne "Total", sort keys %$s), "Total")
    {
        printf $fmt,
               trimmed_file($file, $fw),
               map { $format->($s->{$file}, $_) }
               grep { $options{$_} }
               @{$self->{all_criteria}};

    }

    printf $fmt, "-" x $fw, ("------") x $n;
    print "\n\n";

    select $oldfh;
}

sub add_statement
{
    my $self = shift;
    my ($cc, $sc, $fc) = @_;
    my %line;
    for my $i (0 .. $#$fc)
    {
        my $l = $sc->[$i];
        my $n = $line{$l}++;
        $cc->{$l}[$n] ||= do { my $c; \$c };
        ${$cc->{$l}[$n]} += $fc->[$i];
    }
}

sub add_branch
{
    my $self = shift;
    my ($cc, $sc, $fc) = @_;
    my %line;
    for my $i (0 .. $#$fc)
    {
        my $l = $sc->[$i][0];
        my $n = $line{$l}++;
        if (my $a = $cc->{$l}[$n])
        {
            $a->[0][0] += $fc->[$i][0];
            $a->[0][1] += $fc->[$i][1];
        }
        else
        {
            $cc->{$l}[$n] = [ $fc->[$i], $sc->[$i][1] ];
        }
    }
}

sub add_subroutine
{
    my $self = shift;
    my ($cc, $sc, $fc) = @_;
    my %line;
    for my $i (0 .. $#$fc)
    {
        my $l = $sc->[$i][0];
        my $n = $line{$l}++;
        if (my $a = $cc->{$l}[$n])
        {
            $a->[0] += $fc->[$i];
        }
        else
        {
            $cc->{$l}[$n] = [ $fc->[$i], $sc->[$i][1] ];
        }
    }
}

*add_condition  = \&add_branch;
*add_pod        = \&add_subroutine;
*add_time       = \&add_statement;

sub cover
{
    my $self = shift;

    return $self->{cover} if $self->{cover_valid};

    my %digests;
    my %files;
    my $cover = $self->{cover} = {};
    while (my ($run, $r) = each %{$self->{runs}})
    {
        @{$self->{collected}}{@{$r->{collected}}} = ();
        my $count = $r->{count};
        while (my ($file, $f) = each %$count)
        {
            my $digest = $r->{digest}{$file};
            print STDERR "Devel::Cover: merging data for $file ",
                         "into $digests{$digest}\n"
                if !$files{$file}++ && $digests{$digest};
            my $cf = $cover->{$digests{$digest} ||= $file} ||= {};
            my $st = Devel::Cover::DB::Structure->new
            (
                base   => $self->{base},
                digest => $digest,
            );
            while (my ($criterion, $fc) = each %$f)
            {
                my $get = "get_$criterion";
                my $sc = $st->$get;
                next unless $sc;
                my $cc = $cf->{$criterion} ||= {};
                my $add = "add_$criterion";
                $self->$add($cc, $sc, $fc);
            }
        }
    }

    unless (UNIVERSAL::isa($self->{cover}, "Devel::Cover::DB::Cover"))
    {
        bless $self->{cover}, "Devel::Cover::DB::Cover";
        for my $file (values %{$self->{cover}})
        {
            bless $file, "Devel::Cover::DB::File";
            while (my ($crit, $criterion) = each %$file)
            {
                next if $crit eq "meta";  # ignore meta data
                my $class = "Devel::Cover::" . ucfirst lc $crit;
                bless $criterion, "Devel::Cover::DB::Criterion";
                for my $line (values %$criterion)
                {
                    for my $o (@$line)
                    {
                        die "<$crit:$o>" unless ref $o;
                        bless $o, $class;
                        bless $o, $class . "_" . $o->type if $o->can("type");
                        # print "blessed $crit, $o\n";
                    }
                }
            }
        }
    }

    unless (exists &Devel::Cover::DB::Base::items)
    {
        *Devel::Cover::DB::Base::items = sub
        {
            my $self = shift;
            keys %$self
        };

        *Devel::Cover::DB::Base::values = sub
        {
            my $self = shift;
            values %$self
        };

        *Devel::Cover::DB::Base::get = sub
        {
            my $self = shift;
            my ($get) = @_;
            $self->{$get}
        };

        my $classes =
        {
            Cover     => [ qw( files file ) ],
            File      => [ qw( criteria criterion ) ],
            Criterion => [ qw( locations location ) ],
            Location  => [ qw( data datum ) ],
        };
        my $base = "Devel::Cover::DB::Base";
        while (my ($class, $functions) = each %$classes)
        {
            my $c = "Devel::Cover::DB::$class";
            no strict "refs";
            @{"${c}::ISA"} = $base;
            *{"${c}::$functions->[0]"} = \&{"${base}::values"};
            *{"${c}::$functions->[1]"} = \&{"${base}::get"};
        }

        *Devel::Cover::DB::File::DESTROY = sub {};
        unless (exists &Devel::Cover::DB::File::AUTOLOAD)
        {
            *Devel::Cover::DB::File::AUTOLOAD = sub
            {
                # Work around a change in bleadperl from 12251 to 14899.
                my $func = $Devel::Cover::DB::AUTOLOAD || $::AUTOLOAD;

                # print STDERR "autoloading <$func>\n";
                (my $f = $func) =~ s/^.*:://;
                carp "Undefined subroutine $f called"
                    unless grep { $_ eq $f }
                                @{$self->{all_criteria}},
                                @{$self->{all_criteria_short}};
                no strict "refs";
                *$func = sub { shift->{$f} };
                goto &$func
            };
        }
    }

    $self->{cover_valid} = 1;

    $self->{cover}
}

=for old

sub print_details_hash
{
    my $self = shift;
    my (@files) = @_;
    @files = sort keys %{$self->{cover}} unless @files;
    for my $file (@files)
    {
        print "$file\n\n";
        my $lines = $self->{cover}{$file}{statement};
        my $fmt = "%-5d: %6s %s\n";

        open F, $file or carp("Unable to open $file: $!"), next;

        while (<F>)
        {
            if (exists $lines->{$.})
            {
                my @c = @{$lines->{$.}};
                printf "%5d: %6d %s", $., shift(@c)->[0], $_;
                printf "     : %6d\n", shift(@c)->[0] while @c;
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

sub print_details
{
    my $self = shift;
    my (@files) = @_;
    my $cover = $self->cover;
    @files = sort $cover->items unless @files;
    for my $file (@files)
    {
        print "$file\n\n";
        my $f = $cover->file($file);
        my $statement = $f->statement;
        my $fmt = "%-5d: %6s %s\n";

        open F, $file or carp("Unable to open $file: $!"), next;

        while (<F>)
        {
            if (defined (my $location = $statement->location($.)))
            {
                my @c = @{$location};
                printf "%5d: %6d %s", $., shift(@c)->[0], $_;
                printf "     : %6d\n", shift(@c)->[0] while @c;
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

=cut

1

__END__

=head1 NAME

Devel::Cover::DB - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::DB;

 my $db = Devel::Cover::DB->new(db => "my_coverage_db");
 $db->print_summary(statement => 1, pod => 1);
 $db->print_details;

=head1 DESCRIPTION

This module provides access to a database of code coverage information.

=head1 SEE ALSO

 Devel::Cover

=head1 METHODS

=head2 new

 my $db = Devel::Cover::DB->new(db => "my_coverage_db");

Contructs the DB from the specified database.

=head2 cover

 my $cover = $db->cover;

Returns a Devel::Cover::DB::Cover object.  From here all the coverage
data may be accessed.

 my $cover = $db->cover;
 for my $file ($cover->items)
 {
     print "$file\n";
     my $f = $cover->file($file);
     for my $criterion ($f->items)
     {
         print "  $criterion\n";
         my $c = $f->criterion($criterion);
         for my $location ($c->items)
         {
             my $l = $c->location($location);
             print "    $location @$l\n";
         }
     }
 }

Data for different criteria will be in different formats, so that will
need special handling, but I'll deal with that when we have the data for
different criteria.

If you don't want to remember all the method names, use values() instead
of files(), criteria() and locations() and get() instead of file(),
criterion() and location().

Instead of calling $file->criterion("x") you can also call $file->x.

=head2 is_valid

 my $valid = $db->is_valid;

Returns true iff the db is valid.  (Actually there is one too many fs there, but
that's what it should do.)

=head1 BUGS

Huh?

=head1 VERSION

Version 0.39 - 22nd March 2004

=head1 LICENCE

Copyright 2001-2004, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

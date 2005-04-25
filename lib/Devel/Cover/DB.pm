# Copyright 2001-2005, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB;

use strict;
use warnings;

our $VERSION = "0.53";

use Devel::Cover::Criterion     0.53;
use Devel::Cover::DB::File      0.53;
use Devel::Cover::DB::Structure 0.53;

use Carp;
use File::Path;
use Storable;

my $DB = "cover.12";  # Version 12 of the database.

@Devel::Cover::DB::Criteria =
    (qw( statement branch path condition subroutine pod time ));
@Devel::Cover::DB::Criteria_short =
    (qw( stmt      bran   path cond      sub        pod time ));

sub new
{
    my $class = shift;
    my $self  =
    {
        criteria       => \@Devel::Cover::DB::Criteria,
        criteria_short => \@Devel::Cover::DB::Criteria_short,
        runs           => {},
        collected      => {},
        uncoverable    => [],
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
        mkdir $self->{db}, 0777 or croak "Can't mkdir $self->{db}: $!\n";
    }
    $self->validate_db;

    my $db =
    {
        runs => $self->{runs},
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
        # print STDERR "Devel::Cover: merging run $run <$self->{base}>\n";
        my $r = Devel::Cover::DB->new(base => $self->{base}, db => $run);
        $self->merge($r);
    }
    $self->write($db) if @runs;
    rmtree(\@runs);
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

    # use Data::Dumper; $Data::Dumper::Indent = 1;
    # print "Merging ", Dumper($self), "From ", Dumper($from);

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
                    print STDOUT "Devel::Cover: Deleting old coverage for ",
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

    for (keys %$self)
    {
        $from->{$_} = $self->{$_} unless $_ eq "runs" || $_ eq "collected";
    }

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
    my ($file, $criterion, $part) = @_;
    my $f = $self->{summary}{$file};
    return $f unless $f && defined $criterion;
    my $c = $f->{$criterion};
    $c && defined $part ? $c->{$part} : $c
}

sub calculate_summary
{
    my $self = shift;
    my %options = @_;

    return if exists $self->{summary} && !$options{force};
    my $s = $self->{summary} = {};

    for my $file ($self->cover->items)
    {
        $self->cover->get($file)->calculate_summary($self, $file, \%options);
    }

    # use Data::Dumper; print STDERR Dumper $self;

    for my $file ($self->cover->items)
    {
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

    no warnings "uninitialized";
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
    my ($cc, $sc, $fc, $uc) = @_;
    my %line;
    for my $i (0 .. $#$fc)
    {
        my $l = $sc->[$i];
        unless (defined $l)
        {
            # use Data::Dumper;
            # print STDERR "sc ", scalar @$sc, ", fc ", scalar @$fc, "\n";
            # print STDERR "sc ", Dumper($sc), "fc ", Dumper($fc);
            warn "Devel::Cover: ignoring extra statement\n";
            return;
        }
        my $n = $line{$l}++;
        no warnings "uninitialized";
        $cc->{$l}[$n][0]  += $fc->[$i];
        $cc->{$l}[$n][1] ||= $uc->{$l}[$n][0][1];
    }
    # use Data::Dumper; print Dumper $uc;
    # use Data::Dumper; print Dumper $cc;
}

sub add_time
{
    my $self = shift;
    my ($cc, $sc, $fc) = @_;
    my %line;
    for my $i (0 .. $#$fc)
    {
        my $l = $sc->[$i];
        unless (defined $l)
        {
            # use Data::Dumper;
            # print STDERR "sc ", scalar @$sc, ", fc ", scalar @$fc, "\n";
            # print STDERR "sc ", Dumper($sc), "fc ", Dumper($fc);
            warn "Devel::Cover: ignoring extra statement\n";
            return;
        }
        my $n = $line{$l}++;
        $cc->{$l}[$n] ||= do { my $c; \$c };
        no warnings "uninitialized";
        ${$cc->{$l}[$n]} += $fc->[$i];
    }
}

sub add_branch
{
    my $self = shift;
    my ($cc, $sc, $fc, $uc) = @_;
    my %line;
    for my $i (0 .. $#$fc)
    {
        my $l = $sc->[$i][0];
        unless (defined $l)
        {
            warn "Devel::Cover: ignoring extra branch\n";
            return;
        }
        my $n = $line{$l}++;
        if (my $a = $cc->{$l}[$n])
        {
            no warnings "uninitialized";
            $a->[0][0] += $fc->[$i][0];
            $a->[0][1] += $fc->[$i][1];
            $a->[0][2] += $fc->[$i][2] if exists $fc->[$i][2];
            $a->[0][3] += $fc->[$i][3] if exists $fc->[$i][3];
        }
        else
        {
            $cc->{$l}[$n] = [ $fc->[$i], $sc->[$i][1] ];
        }
        $cc->{$l}[$n][2][$_->[0]] ||= $_->[1] for @{$uc->{$l}[$n]};
    }
}

sub add_subroutine
{
    my $self = shift;
    my ($cc, $sc, $fc, $uc) = @_;
    my %line;
    for my $i (0 .. $#$fc)
    {
        my $l = $sc->[$i][0];
        unless (defined $l)
        {
            # use Data::Dumper;
            # print STDERR "sc ", scalar @$sc, ", fc ", scalar @$fc, "\n";
            # print STDERR "sc ", Dumper($sc), "fc ", Dumper($fc);
            warn "Devel::Cover: ignoring extra subroutine\n";
            return;
        }
        my $n = $line{$l}++;
        if (my $a = $cc->{$l}[$n])
        {
            no warnings "uninitialized";
            $a->[0] += $fc->[$i];
        }
        else
        {
            $cc->{$l}[$n] = [ $fc->[$i], $sc->[$i][1] ];
        }
        $cc->{$l}[$n][2] ||= $uc->{$l}[$n][0][1];
    }
}

*add_condition = \&add_branch;
*add_pod       = \&add_subroutine;

sub uncoverable_files
{
    my $self = shift;
    my $f = ".uncoverable";
    (@{$self->{uncoverable}}, $f, glob("~/$f"))
}

sub uncoverable
{
    my $self = shift;

    my $u = {};

    for my $file ($self->uncoverable_files)
    {
        open F, $file or next;
        print STDOUT "Reading uncoverable information from $file\n"
            unless $Devel::Cover::Silent;
        while (<F>)
        {
            chomp;
            my ($file, $crit, $line, $count, $type, $reason) = split " ", $_, 6;
            push @{$u->{$file}{$crit}{$line}[$count]}, [$type, $reason];
        }
    }

    # use Data::Dumper; $Data::Dumper::Indent = 1; print Dumper $u;

    for my $file (sort keys %$u)
    {
        # print STDERR "Reading $file\n";
        unless (open F, $file)
        {
            warn "Devel::Cover: Can't open file $file: $!\n";
            next;
        }
        my $df = Digest::MD5->new;
        my %dl;
        my $ln = 0;
        while (<F>)
        {
            # print STDERR "read [$.][$_]\n";
            $dl{Digest::MD5->new->add($_)->hexdigest} = ++$ln;
            $df->add($_);
        }
        close F;
        my $f = $u->{$file};
        # use Data::Dumper; $Data::Dumper::Indent = 1; print STDERR Dumper $f;
        for my $crit (keys %$f)
        {
            my $c = $f->{$crit};
            for my $line (keys %$c)
            {
                if (exists $dl{$line})
                {
                    # print STDERR "Found uncoverable $file:$crit:$line -> $dl{$line}\n";
                    $c->{$dl{$line}} = delete $c->{$line};
                }
                else
                {
                    warn "Devel::Cover: Can't find line for uncovered data: " .
                         "$file $crit $line\n";
                    delete $c->{$line};
                }
            }
        }
        $u->{$df->hexdigest} = delete $u->{$file};
    }

    $u
}

sub add_uncoverable
{
    my $self = shift;
    my ($adds) = @_;
    for my $add (@$adds)
    {
        my ($file, $crit, $line, $count, $type, $reason) = split " ", $add, 6;
        my ($uncoverable_file) = $self->uncoverable_files;
        open U, ">>", $uncoverable_file
            or die "Devel::Cover: Can't open $uncoverable_file: $!\n";

        unless (open F, $file)
        {
            warn "Devel::Cover: Can't open $file: $!";
            next;
        }
        while (<F>)
        {
            last if $. == $line;
        }
        if (defined)
        {
            my $dl = Digest::MD5->new->add($_)->hexdigest;
            print U "$file $crit $dl $count $type $reason\n";
        }
        else
        {
            warn "Devel::Cover: Can't find line $line in $file.  ",
                 "Last line is $.\n";
        }
        close F or die "Devel::Cover: Can't close $file: $!\n";
    }
}

sub delete_uncoverable
{
    my $self = shift;
}

sub clean_uncoverable
{
    my $self = shift;
}

sub cover
{
    my $self = shift;

    return $self->{cover} if $self->{cover_valid};

    my %digests;
    my %files;
    my $cover = $self->{cover} = {};
    my $uncoverable = $self->uncoverable;
    my $st = Devel::Cover::DB::Structure->new(base => $self->{base})->read_all;

    while (my ($run, $r) = each %{$self->{runs}})
    {
        @{$self->{collected}}{@{$r->{collected}}} = ();
        $st->add_criteria(@{$r->{collected}});
        my $count = $r->{count};
        while (my ($file, $f) = each %$count)
        {
            # print "Looking at <$file>\n";
            my $digest = $r->{digest}{$file};
            unless ($digest)
            {
                print STDERR "Devel::Cover: Can't find digest for $file\n";
                next;
            }
            # print STDERR "File: $file\n";
            print STDERR "Devel::Cover: merging data for $file ",
                         "into $digests{$digest}\n"
                if !$files{$file}++ && $digests{$digest};
            my $cf = $cover->{$digests{$digest} ||= $file} ||= {};
            # print "Structure from $st->{file}\n";
            # use Data::Dumper;
            # print STDERR "st ", Dumper($st),
                         # "f  ", Dumper($f),
                         # "uc ", Dumper($uncoverable->{$digest});
            while (my ($criterion, $fc) = each %$f)
            {
                my $get = "get_$criterion";
                my $sc  = $st->$get($file);
                next unless $sc;  # TODO - why?
                my $cc  = $cf->{$criterion} ||= {};
                my $add = "add_$criterion";
                $self->$add($cc, $sc, $fc, $uncoverable->{$digest}{$criterion});
                # $cc - coverage being filled in
                # $sc - structure information
                # $fc - coverage from this file
                # $uc - uncoverable information
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
        bless $_, "Devel::Cover::DB::Run" for values %{$self->{runs}};
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
                (my $f = $func) =~ s/.*:://;
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

sub runs
{
    my $self = shift;
    $self->cover unless $self->{cover_valid};
    values %{$self->{runs}}
}

package Devel::Cover::DB::Run;

our $AUTOLOAD;

sub DESTROY {}

sub AUTOLOAD
{
    my $func = $AUTOLOAD;
    # print STDERR "autoloading <$func>\n";
    (my $f = $func) =~ s/.*:://;
    no strict "refs";
    *$func = sub { shift->{$f} };
    goto &$func
}

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

Version 0.53 - 17th April 2005

=head1 LICENCE

Copyright 2001-2005, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

# Copyright 2001-2012, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB;

use strict;
use warnings;

# VERSION

use Devel::Cover::Criterion;
use Devel::Cover::DB::File;
use Devel::Cover::DB::Structure;
use Devel::Cover::DB::IO;

use Carp;
use File::Path;

use Devel::Cover::Dumper;  # For debugging

my $DB = "cover.13";  # Version 13 of the database.

@Devel::Cover::DB::Criteria =
    (qw( statement branch path condition subroutine pod time ));
@Devel::Cover::DB::Criteria_short =
    (qw( stmt      bran   path cond      sub        pod time ));
$Devel::Cover::DB::Ignore_filenames =
    qr/   # Moose
        (?:
            (?:
                reader | writer | constructor | destructor | accessor |
                predicate | clearer | native \s delegation \s method |
                # Template Toolkit
                Parser\.yp
            )
            \s .* \s
            (?: \( defined \s at \s .* \s line \s \d+ \) | defined \s at )
        )
        | # Moose
        (?: generated \s method \s \( unknown \s origin \) )
        | # Mouse
        (?: (?: rw-accessor | ro-accessor ) \s for )
        | # Template Toolkit
        (?: Parser\.yp )
      /x;

sub new
{
    my $class = shift;
    my $self  =
    {
        criteria         => \@Devel::Cover::DB::Criteria,
        criteria_short   => \@Devel::Cover::DB::Criteria_short,
        runs             => {},
        collected        => {},
        uncoverable_file => [],
        @_
    };

    $self->{all_criteria}       = [ @{$self->{criteria}},       "total" ];
    $self->{all_criteria_short} = [ @{$self->{criteria_short}}, "total" ];
    $self->{base} ||= $self->{db};
    bless $self, $class;

    if (defined $self->{db})
    {
        $self->validate_db;
        my $file = "$self->{db}/$DB";
        $self->read($file) if -e $file;
    }

    $self
}

sub     criteria       { @{$_[0]->{    criteria      }} }
sub     criteria_short { @{$_[0]->{    criteria_short}} }
sub all_criteria       { @{$_[0]->{all_criteria      }} }
sub all_criteria_short { @{$_[0]->{all_criteria_short}} }

sub read
{
    my $self   = shift;
    my ($file) = @_;

    my $io     = Devel::Cover::DB::IO->new;
    my $db     = $io->read($file);
    $self->{runs} = $db->{runs};
    $self
}

sub write
{
    my $self = shift;
    $self->{db} = shift if @_;

    croak "No db specified" unless length $self->{db};
    unless (mkdir $self->{db})
    {
        croak "Can't mkdir $self->{db}: $!\n" unless -d $self->{db};
    }
    $self->validate_db;

    my $db = { runs => $self->{runs} };
    my $io = Devel::Cover::DB::IO->new;
    $io->write($db, "$self->{db}/$DB");
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

    return $self unless -d $db;

    # TODO - just delete the directory?
    opendir DIR, $db or die "Can't opendir $db: $!";
    my @files = map "$db/$_", map /(.*)/ && $1, grep !/^\.\.?/, readdir DIR;
    closedir DIR or die "Can't closedir $db: $!";
    rmtree(\@files) if @files;

    $self
}

sub merge_runs
{
    my $self = shift;
    my $db = $self->{db};
    # print STDERR "merge_runs from $db/runs/*\n";
    # system "ls -al $db/runs";
    return $self unless length $db;
    opendir DIR, "$db/runs" or return $self;
    my @runs = map "$db/runs/$_", grep !/^\.\.?/, readdir DIR;
    closedir DIR or die "Can't closedir $db/runs: $!";

    $self->{changed_files} = {};

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

    if (keys %{$self->{changed_files}})
    {
        my $st = Devel::Cover::DB::Structure->new(base => $self->{base});
        $st->read_all;
        for my $file (sort keys %{$self->{changed_files}})
        {
            # print STDERR "dealing with changed file <$file>\n";
            $st->delete_file($file);
        }
        $st->write($self->{base});
    }

    $self
}

sub validate_db
{
    my $self = shift;

    # Check validity of the db.  It is valid if the $DB file is there, or if it
    # is not there but the db directory is empty, or if there is no db
    # directory.
    # die if the db is invalid.

    # just warn for now
    print STDERR "Devel::Cover: $self->{db} is an invalid database\n"
        unless $self->is_valid;

    $self
}

sub exists
{
    my $self = shift;
    -d $self->{db}
}

sub is_valid
{
    my $self = shift;
    return 1 if !-e $self->{db};
    return 1 if -e "$self->{db}/$DB";
    opendir my $fh, $self->{db} or return 0;
    for my $file (readdir $fh)
    {
        next if $file eq "." || $file eq "..";
        next if $file =~ /(?:runs|structure|debuglog|digests)$/
                && -e "$self->{db}/$file";
        warn "found $file in $self->{db}";
        return 0;
    }
    closedir $fh
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

    # print STDERR "Merging ", Dumper($self), "From ", Dumper($from);

    while (my ($fname, $frun) = each %{$from->{runs}})
    {
        while (my ($file, $digest) = each %{$frun->{digests}})
        {
            while (my ($name, $run) = each %{$self->{runs}})
            {
                # print STDERR
                #     "digests for $file: $digest, $run->{digests}{$file}\n";
                if ($run->{digests}{$file} && $digest &&
                    $run->{digests}{$file} ne $digest)
                {
                    # File has changed.  Delete old coverage instead of merging.
                    print STDOUT "Devel::Cover: Deleting old coverage for ",
                                               "changed file $file\n"
                        unless $Devel::Cover::Silent;
                    delete $run->{digests}{$file};
                    delete $run->{count}  {$file};
                    delete $run->{vec}    {$file};
                    $self->{changed_files}{$file}++;
                }
            }
        }
    }

    _merge_hash($self->{runs},      $from->{runs});
    _merge_hash($self->{collected}, $from->{collected});

    return $self;  # TODO - what's going on here?

    # When the database gets big, it's quicker to merge into what's
    # already there.

    _merge_hash($from->{runs},      $self->{runs});
    _merge_hash($from->{collected}, $self->{collected});

    for (keys %$self)
    {
        $from->{$_} = $self->{$_} unless $_ eq "runs" || $_ eq "collected";
    }

    # print STDERR "Giving ", Dumper($from);

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

    # print STDERR Dumper $self;

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
        # print STDERR "statement: $i\n";
        my $l = $sc->[$i];
        unless (defined $l)
        {
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
    # print STDERR Dumper $uc;
    # print STDERR "cc: ", Dumper $cc;
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

    # print STDERR "add_subroutine():\n", Dumper $cc, $sc, $fc, $uc;

    # $cc = { line_number => [ [ count, sub_name, uncoverable ], [ ... ] ], .. }
    # $sc = [ [ line_number, sub_name ], [ ... ] ]
    # $fc = [ count, ... ]
    # $uc = { line_number => [ [ ??? ], [ ... ] ], ... }
    # length @$sc == length @$fc

    my %line;
    for my $i (0 .. $#$fc)
    {
        my $l = $sc->[$i][0];
        unless (defined $l)
        {
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
    (@{$self->{uncoverable_file}}, $f, glob("~/$f"))
}

sub uncoverable
{
    my $self = shift;

    my $u = {};  # holds all the uncoverable information

    # First populate $u with the uncoverable information directly from the
    # .uncoverable files.  Then loop through the information converting it to
    # the format we will use later to manage the uncoverable code.  The
    # primary changes are converting MD5 digests of lines to line numbers, and
    # converting filenames to MD5 digests of the files.

    for my $file ($self->uncoverable_files)
    {
        open my $f, "<", $file or next;
        print STDOUT "Reading uncoverable information from $file\n"
            unless $Devel::Cover::Silent;
        while (<$f>)
        {
            chomp;
            my ($file, $crit, $line, $count, $type, $class, $note) =
                split " ", $_, 7;
            push @{$u->{$file}{$crit}{$line}[$count]}, [$type, $class, $note];
        }
    }

    # print STDERR Dumper $u;
    # Now change the format of the uncoverable information.

    for my $file (sort keys %$u)
    {
        # print STDERR "Reading $file\n";
        open my $fh, "<", $file or do
        {
            warn "Devel::Cover: Can't open file $file: $!\n";
            next;
        };
        my $df = Digest::MD5->new;  # MD5 digest of the file
        my %dl;                     # maps MD5 digests of lines to line numbers
        my $ln = 0;                 # line number
        while (<$fh>)
        {
            # print STDERR "read [$.][$_]\n";
            $dl{Digest::MD5->new->add($_)->hexdigest} = ++$ln;
            $df->add($_);
        }
        close $fh;
        my $f = $u->{$file};
        # print STDERR Dumper $f;
        for my $crit (keys %$f)
        {
            my $c = $f->{$crit};
            for my $line (keys %$c)
            {
                if (exists $dl{$line})
                {
                    # print STDERR
                    # "Found uncoverable $file:$crit:$line -> $dl{$line}\n";

                    # Change key from the MD5 digest to the actual line number.
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
        # Change the key from the filename to the MD5 digest of the file.
        $u->{$df->hexdigest} = delete $u->{$file};
    }

    print STDERR Dumper $u;
    $u
}

sub add_uncoverable
{
    my $self = shift;
    my ($adds) = @_;
    for my $add (@$adds)
    {
        my ($file, $crit, $line, $count, $type, $class, $note) =
            split " ", $_, 7;
        my ($uncoverable_file) = $self->uncoverable_files;

        open my $f, "<", $file or do
        {
            warn "Devel::Cover: Can't open $file: $!";
            next;
        };
        while (<$f>)
        {
            last if $. == $line;
        }
        if (defined)
        {
            open my $u, ">>", $uncoverable_file
                or die "Devel::Cover: Can't open $uncoverable_file: $!\n";
            my $dl = Digest::MD5->new->add($_)->hexdigest;
            print $u "$file $crit $dl $count $type $class $note\n";
        }
        else
        {
            warn "Devel::Cover: Can't find line $line in $file.  ",
                 "Last line is $.\n";
        }
        close $f or die "Devel::Cover: Can't close $file: $!\n";
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

sub uncoverable_comments
{
    my $self = shift;
    my ($uncoverable, $file, $digest) = @_;

    my $cr = join "|", @{$self->{all_criteria}};
    my $uc = qr/(.*)# uncoverable ($cr)(.*)/;  # regex for uncoverable comments
    my %types =
    (
        branch    => { true => 0, false => 1 },
        condition => { left => 0, right => 1, false => 2 },
    );

    # Look for uncoverable comments
    open my $fh, "<", $file or do
    {
        warn "Devel::Cover: Can't open file $file: $!\n";
        next;
    };
    my @waiting;
    while (<$fh>)
    {
        chomp;
        # print STDERR "read [$.][$_]\n";
        next unless /$uc/ || @waiting;
        if ($2)
        {
            my ($code, $criterion, $info)     = ($1, $2, $3);
            my ($count, $class, $note, $type) = (1, "default", "");

            if ($criterion eq "branch" || $criterion eq "condition")
            {
                if ($info =~ /^\s*(\w+)(?:\s|$)/)
                {
                    my $t = $1;
                    $type = $types{$criterion}{$t};
                    unless (defined $type)
                    {
                        warn "Unknown type $t found parsing " .
                             "uncoverable $criterion at $file:$.\n";
                        $type = 999;  # partly magic number
                    }
                }
            }
            $count = $1 if $info =~ /count:(\d+)/;
            $class = $1 if $info =~ /class:(\w+)/;
            $note  = $1 if $info =~ /note:(.+)/;

            # no warnings "uninitialized";
            # warn "pushing $criterion, $count, $type, $class, $note";

            push @waiting,
                 [$criterion, $count - 1, $type, $class, $note];

            next unless $code =~ /\S/;
        }

        # found what we are waiting for
        while (my $w = shift @waiting)
        {
            my ($criterion, $count, $type, $class, $note) = @$w;
            push @{$uncoverable->{$digest}{$criterion}{$.}[$count]},
                 [$type, $class, $note];
        }
    }
    close $fh;

    warn scalar @waiting,
         " unmatched uncoverable comments not found at end of $file\n"
        if @waiting;

    # TODO - read in and merge $self->uncoverable;
    # print Dumper $uncoverable;
}

sub objectify_cover
{
    my $self = shift;

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
        for my $r (keys %{$self->{runs}})
        {
            if (defined $self->{runs}{$r})
            {
                bless $self->{runs}{$r}, "Devel::Cover::DB::Run";
            }
            else
            {
                delete $self->{runs}{$r};  # DEVEL_COVER_SELF
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
}

sub cover
{
    my $self = shift;

    return $self->{cover} if $self->{cover_valid};

    my %digests;  # mapping of digests to canonical filenames
    my %files;    # processed files
    my $cover = $self->{cover} = {};
    my $uncoverable = {};
    my $st = Devel::Cover::DB::Structure->new(base => $self->{base})->read_all;
    my @runs = sort { $self->{runs}{$b}{start} <=> $self->{runs}{$a}{start} }
                    keys %{$self->{runs}};
    # print STDERR "runs: ", Dumper $self->{runs};

    for my $run (@runs)
    {
        last unless $st;

        my $r = $self->{runs}{$run};
        next unless $r->{collected};  # DEVEL_COVER_SELF
        @{$self->{collected}}{@{$r->{collected}}} = ();
        $st->add_criteria(@{$r->{collected}});
        my $count = $r->{count};
        # print STDERR "run $run, count: ", Dumper $count;
        while (my ($file, $f) = each %$count)
        {
            my $digest = $r->{digests}{$file};
            unless ($digest)
            {
                print STDERR "Devel::Cover: Can't find digest for $file\n"
                    unless $Devel::Cover::Silent ||
                           $file =~ $Devel::Cover::DB::Ignore_filenames ||
                           ($Devel::Cover::Self_cover &&
                            $file =~ q|/Devel/Cover[./]|);
                next;
            }
            # print STDERR "File: $file\n";
            print STDERR "Devel::Cover: merging data for $file ",
                         "into $digests{$digest}\n"
                if !$files{$file}++ && $digests{$digest};

            $self->uncoverable_comments($uncoverable, $file, $digest)
                unless $digests{$digest};

            # Set up data structure to hold coverage being filled in
            my $cf = $cover->{$digests{$digest} ||= $file} ||= {};

            # print STDERR "st ", Dumper($st),
                         # "f  ", Dumper($f),
                         # "uc ", Dumper($uncoverable->{$digest});
            while (my ($criterion, $fc) = each %$f)
            {
                my $get = "get_$criterion";
                my $sc  = $st->$get($digest);
                # print STDERR "$criterion: ", Dumper $sc, $fc;
                unless ($sc)
                {
                    print STDERR "Devel::Cover: Can't locate structure for ",
                                 "$criterion in $file\n";
                    next;
                }
                my $cc  = $cf->{$criterion} ||= {};
                my $add = "add_$criterion";
                # print STDERR "$add():\n", Dumper $cc, $sc, $fc;
                $self->$add($cc, $sc, $fc, $uncoverable->{$digest}{$criterion});
                # print STDERR "--> $add():\n", Dumper $cc;
                # $cc - coverage being filled in
                # $sc - structure information
                # $fc - coverage from this file
                # $uc - uncoverable information
            }
        }
        # print STDERR "Cover: ", Dumper $cover;
    }

    $self->objectify_cover;
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

Data for different criteria will be in different formats, so that will need
special handling.  This is not yet documented so your best bet for now is to
look at some of the simpler reports and/or the source.

The methods in the above example are actually aliases for methods in
Devel::Cover::DB::Base (the base class for all Devel::Cover::DB::* classes):

=over

=item * Devel::Cover::DB::Base->values

Aliased to Devel::Cover::DB::Cover->files, Devel::Cover::DB::File->criteria,
Devel::Cover::DB::Criterion->locations, and Devel::Cover::DB::Location->data

=item * Devel::Cover::DB::Base->get

Aliased to Devel::Cover::DB::Cover->file, Devel::Cover::DB::File->criteriom,
Devel::Cover::DB::Criterion->location, and Devel::Cover::DB::Location->datum

=back

Instead of calling $file->criterion("x") you can also call $file->x.

=head2 is_valid

 my $valid = $db->is_valid;

Returns true if $db is valid (or looks valid, the function is too lax).

=head1 SEE ALSO

 Devel::Cover
 Devel::Cover::DB::Base
 Devel::Cover::DB::Cover
 Devel::Cover::DB::File
 Devel::Cover::DB::Criterion
 Devel::Cover::DB::Location

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2001-2012, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

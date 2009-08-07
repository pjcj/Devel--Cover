# Copyright 2001-2008, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover;

use strict;
use warnings;

our $VERSION = "0.64";

use DynaLoader ();
our @ISA = "DynaLoader";

use Devel::Cover::DB  0.64;
use Devel::Cover::Inc 0.64;

use B qw( class ppname main_cv main_start main_root walksymtable OPf_KIDS );
use B::Debug;
use B::Deparse;

use Carp;
use Config;
use Cwd "abs_path";
use File::Spec;

BEGIN
{
    # Use Pod::Coverage if it is available.
    eval "use Pod::Coverage 0.06";
    # If there is any error other than a failure to locate, report it.
    die $@ if $@ && $@ !~ m/Can't locate Pod\/Coverage.+pm in \@INC/;

    # We'll prefer Pod::Coverage::CountParents
    eval "use Pod::Coverage::CountParents";
    die $@ if $@ && $@ !~ m/Can't locate Pod\/Coverage.+pm in \@INC/;
}

# $SIG{__DIE__} = \&Carp::confess;

my $Initialised;                         # import() has been called.

my $Dir;                                 # Directory in which coverage will be
                                         # collected.
my $DB        = "cover_db";              # DB name.
my $Merge     = 1;                       # Merge databases.
my $Summary   = 1;                       # Output coverage summary.
my $Subs_only = 0;                       # Coverage only for sub bodies.

my @Ignore;                              # Packages to ignore.
my @Inc;                                 # Original @INC to ignore.
my @Select;                              # Packages to select.
my @Ignore_re;                           # Packages to ignore.
my @Inc_re;                              # Original @INC to ignore.
my @Select_re;                           # Packages to select.

my $Pod = $INC{"Pod/Coverage/CountParents.pm"} ? "Pod::Coverage::CountParents" :
          $INC{"Pod/Coverage.pm"}              ? "Pod::Coverage"               :
          "";                            # Type of pod coverage available.
my %Pod;                                 # Pod coverage data.

my @Cvs;                                 # All the Cvs we want to cover.
my @Subs;                                # All the subs we want to cover.
my $Cv;                                  # Cv we are looking in.
my $Sub_name;                            # Name of the sub we are looking in.
my $Sub_count;                           # Count for multiple subs on same line.

my $Coverage;                            # Raw coverage data.
my $Structure;                           # Structure of the files.

my %Criteria;                            # Names of coverage criteria.
my %Coverage;                            # Coverage criteria to collect.
my %Coverage_options;                    # Options for overage criteria.

my %Run;                                 # Data collected from the run.

use vars '$File',                        # Last filename we saw.  (localised)
         '$Line',                        # Last line number we saw.  (localised)
         '$Collect',                     # Whether or not we are collecting
                                         # coverage data.  We make two passes
                                         # over conditions.  (localised)
         '%Files',                       # Whether we are interested in files.
                                         # Used in runops function.
         '$Silent';                      # Output nothing. Can be used anywhere.

BEGIN
{
    ($File, $Line, $Collect) = ("", 0, 1);
    $Silent = ($ENV{HARNESS_PERL_SWITCHES} || "") =~ /Devel::Cover/ ||
              ($ENV{PERL5OPT}              || "") =~ /Devel::Cover/;
    *OUT = $ENV{DEVEL_COVER_DEBUG} ? *STDERR : *STDOUT;
}

if (0 && $Config{useithreads})
{
    eval "use threads";

    no warnings "redefine";

    my $original_join;
    BEGIN { $original_join = \&threads::join }
    # print STDERR "original_join: $original_join\n";

    # $original_join = sub { print STDERR "j\n" };

    # sub threads::join
    *threads::join = sub
    {
        # print STDERR "threads::join- ", \&threads::join, "\n";
        # print STDERR "original_join- $original_join\n";
        my $self = shift;
        print STDERR "(joining thread ", $self->tid, ")\n";
        my @ret = $original_join->($self, @_);
        print STDERR "(returning <@ret>)\n";
        @ret
    };

    my $original_destroy;
    BEGIN { $original_destroy = \&threads::DESTROY }

    *threads::DESTROY = sub
    {
        my $self = shift;
        print STDERR "(destroying thread ", $self->tid, ")\n";
        $original_destroy->($self, @_);
    };

    # print STDERR "threads::join: ", \&threads::join, "\n";

    my $new = \&threads::new;
    *threads::new = *threads::create = sub
    {
        my $class     = shift;
        my $sub       = shift;
        my $wantarray = wantarray;

        $new->($class,
               sub
               {
                   print STDERR "Starting thread\n";
                   set_coverage(keys %Coverage);
                   my $ret = [ $sub->(@_) ];
                   print STDERR "Ending thread\n";
                   report() if $Initialised;
                   print STDERR "Ended thread\n";
                   $wantarray ? @{$ret} : $ret->[0];
               },
               @_
              );
    };
}

BEGIN { @Inc = @Devel::Cover::Inc::Inc; @Ignore = ("/Devel/Cover[./]") }
# BEGIN { $^P = 0x004 | 0x010 | 0x100 | 0x200 }
# BEGIN { $^P = 0x004 | 0x100 | 0x200 }
BEGIN { $^P = 0x004 | 0x100 }

{
    sub check
    {
        return unless $Initialised;

        check_files();

        set_coverage(keys %Coverage);
        my @coverage = get_coverage();
        %Coverage = map { $_ => 1 } @coverage;

        delete $Coverage{path};  # not done yet
        my $nopod = "";
        if (!$Pod && exists $Coverage{pod})
        {
            delete $Coverage{pod};  # Pod::Coverage unavailable
            $nopod = <<EOM;
    Pod coverage is unavailable.  Please install Pod::Coverage from CPAN.
EOM
        }

        set_coverage(keys %Coverage);
        @coverage = get_coverage();
        my $last = pop @coverage || "";

        print OUT __PACKAGE__, " $VERSION: Collecting coverage data for ",
              join(", ", @coverage),
              @coverage ? " and " : "",
              "$last.\n",
              $nopod,
              $Subs_only     ? "    Collecting for subroutines only.\n" : "",
              $ENV{MOD_PERL} ? "    Collecting under $ENV{MOD_PERL}\n"  : "",
              "Selecting packages matching:", join("\n    ", "", @Select), "\n",
              "Ignoring packages matching:",  join("\n    ", "", @Ignore), "\n",
              "Ignoring packages in:",        join("\n    ", "", @Inc),    "\n"
            unless $Silent;

        $Run{OS}    = $^O;
        $Run{perl}  = join ".", map ord, split //, $^V;
        $Run{run}   = $0;
        $Run{start} = get_elapsed();
    }

    no warnings "void";  # avoid "Too late to run CHECK block" warning
    CHECK { check }
}

{
    my $run_end = 0;
    sub first_end
    {
        # print STDERR "**** END 1 - $run_end\n";
        set_last_end() unless $run_end++
    }

    my $run_init = 0;
    sub first_init
    {
        # print STDERR "**** INIT 1 - $run_init\n";
        collect_inits() unless $run_init++
    }
}

sub last_end
{
    # print STDERR "**** END 2 - [$Initialised]\n";
    report() if $Initialised;
    # print STDERR "**** END 2 - ended\n";
}

{
    no warnings "void";  # avoid "Too late to run ... block" warning
    INIT  {}  # dummy sub to make sure PL_initav is set up and populated
    END   {}  # dummy sub to make sure PL_endav  is set up and populated
    CHECK { set_first_init_and_end() }  # we really want to be first
}

sub CLONE
{
    # return;

    print STDERR <<EOM;

Unfortunately, Devel::Cover does not yet work with threads.  I have done
some work in this area, but there is still more to be done.

EOM
    require POSIX;
    POSIX::_exit(1);
}

sub import
{
    return if $Initialised;

    my $class = shift;

    my @o = (@_, split ",", $ENV{DEVEL_COVER_OPTIONS} || "");
    # print STDERR __PACKAGE__, ": Parsing options from [@_]\n";

    my $blib = -d "blib";
    @Inc     = () if "@o" =~ /-inc /;
    @Ignore  = () if "@o" =~ /-ignore /;
    @Select  = () if "@o" =~ /-select /;
    while (@o)
    {
        local $_ = shift @o;
        /^-silent/    && do { $Silent    = shift @o; next };
        /^-dir/       && do { $Dir       = shift @o; next };
        /^-db/        && do { $DB        = shift @o; next };
        /^-merge/     && do { $Merge     = shift @o; next };
        /^-summary/   && do { $Summary   = shift @o; next };
        /^-blib/      && do { $blib      = shift @o; next };
        /^-subs_only/ && do { $Subs_only = shift @o; next };
        /^-coverage/  &&
            do { $Coverage{+shift @o} = 1 while @o && $o[0] !~ /^[-+]/; next };
        /^[-+]ignore/ &&
            do { push @Ignore,   shift @o while @o && $o[0] !~ /^[-+]/; next };
        /^[-+]inc/    &&
            do { push @Inc,      shift @o while @o && $o[0] !~ /^[-+]/; next };
        /^[-+]select/ &&
            do { push @Select,   shift @o while @o && $o[0] !~ /^[-+]/; next };
        warn __PACKAGE__ . ": Unknown option $_ ignored\n";
    }

    if (defined $Dir)
    {
        # Die tainting.
        # Anyone using this module can do worse things than messing with
        # tainting.
        $Dir = $1 if $Dir =~ /(.*)/;
        chdir $Dir or die __PACKAGE__ . ": Can't chdir $Dir: $!\n";
    }
    else
    {
        $Dir = $1 if Cwd::getcwd() =~ /(.*)/;
    }

    unless (-d $DB)
    {
        # Nasty hack to keep 5.6.1 happy.
        mkdir $DB, 0700 or croak "Can't mkdir $DB: $!\n";
        chmod 0700, $DB or croak "Can't chmod $DB: $!\n";
    }
    $DB = $1 if Cwd::abs_path($DB) =~ /(.*)/;
    Devel::Cover::DB->delete($DB) unless $Merge;

    if ($blib)
    {
        eval "use blib";
        for (@INC) { $_ = $1 if /(.*)/ }  # Die tainting.
        push @Ignore, "^t/", '\\.t$', '^test\\.pl$';
    }

    my $ci = $^O eq "MSWin32";
    @Select_re = map qr/$_/,                           @Select;
    @Ignore_re = map qr/$_/,                           @Ignore;
    @Inc_re    = map $ci ? qr/^\Q$_\//i : qr/^\Q$_\//, @Inc;
    %Files     = ();  # start gathering file information from scratch

    for my $c (Devel::Cover::DB->new->criteria)
    {
        my $func = "coverage_$c";
        no strict "refs";
        $Criteria{$c} = $func->();
    }

    %Coverage = (all => 1) unless keys %Coverage;
    for (keys %Coverage)
    {
        my @c = split /-/, $_;
        if (@c > 1)
        {
            $Coverage{shift @c} = \@c;
            delete $Coverage{$_};
        }
    }
    %Coverage_options = %Coverage;

    $Initialised = 1;

    if ($ENV{MOD_PERL})
    {
        eval "BEGIN {}";
        check();
        set_first_init_and_end();
    }
}

sub cover_names_to_val
{
    my $val = 0;
    for my $c (@_)
    {
        if (exists $Criteria{$c})
        {
            $val |= $Criteria{$c};
        }
        elsif ($c eq "all" || $c eq "none")
        {
            my $func = "coverage_$c";
            no strict "refs";
            $val |= $func->();
        }
        else
        {
            warn __PACKAGE__ . qq(: Unknown coverage criterion "$c" ignored.\n);
        }
    }
    $val;
}

sub set_coverage
{
    set_criteria(cover_names_to_val(@_));
}

sub add_coverage
{
    add_criteria(cover_names_to_val(@_));
}

sub remove_coverage
{
    remove_criteria(cover_names_to_val(@_));
}

sub get_coverage
{
    return unless defined wantarray;
    my @names;
    my $val = get_criteria();
    for my $c (sort keys %Criteria)
    {
        push @names, $c if $val & $Criteria{$c};
    }
    return wantarray ? @names : "@names";
}

{

my %File_cache;

sub normalised_file
{
    my ($file) = @_;

    return $File_cache{$file} if exists $File_cache{$file};

    my $f = $file;
    $file =~ s/ \(autosplit into .*\)$//;
    # print STDERR "file is <$file>\n";
    # use Data::Dumper;
    # print STDERR "file is <$file>\ncoverage: ", Dumper coverage(0);
    if (exists coverage(0)->{module} && exists coverage(0)->{module}{$file} &&
        !File::Spec->file_name_is_absolute($file))
    {
        my $m = coverage(0)->{module}{$file};
        # print STDERR "Loaded <$file> <$m->[0]> from <$m->[1]> ";
        $file = File::Spec->rel2abs($file, $m->[1]);
        # print STDERR "as <$file> ";
    }
    if ($] >= 5.008)
    {
        if ($^O eq "MSWin32" || $^O eq "cygwin")
        {
            # TODO - Windows seems busted here
        }
        else
        {
            # print STDERR "getting abs_path <$file> ";
            my $abs;
            $abs = abs_path($file) unless -l $file;  # leave symbolic links
            # print STDERR "giving <$file> ";
            $file = $abs if defined $abs;
        }
        # print STDERR "finally <$file> <$Dir>\n";
    }
    $file =~ s|\\|/|g if $^O eq "MSWin32";
    $file =~ s|^$Dir/||;

    # print STDERR "File: $f => $file\n";

    $File_cache{$f} = $file
}

}

sub get_location
{
    my ($op) = @_;

    $File = $op->file;
    $Line = $op->line;
    # warn "${File}::$Line\n";

    # If there's an eval, get the real filename.  Enabled from $^P & 0x100.
    ($File, $Line) = ($1, $2) if $File =~ /^\(eval \d+\)\[(.*):(\d+)\]/;
    $File = normalised_file($File);

    if (!exists $Run{vec}{$File} && $Run{collected})
    {
        my %vec;
        @vec{@{$Run{collected}}} = ();
        delete $vec{time};
        $vec{subroutine}++ if exists $vec{pod};
        @{$Run{vec}{$File}{$_}}{"vec", "size"} = ("", 0) for keys %vec;
    }
}

sub use_file
{
    my ($file) = @_;

    # die "bad file" unless length $file;

    $file = $1 if $file =~ /^\(eval \d+\)\[(.*):\d+\]/;
    $file =~ s/ \(autosplit into .*\)$//;

    return $Files{$file} if exists $Files{$file};

    my $f = normalised_file($file);

    # print STDERR "checking <$file> <$f> against ",
                 # "select(@Select_re), ignore(@Ignore_re), inc(@Inc_re)\n";

    for (@Select_re) { return $Files{$file} = 1 if $f =~ $_ }
    for (@Ignore_re) { return $Files{$file} = 0 if $f =~ $_ }
    for (@Inc_re)    { return $Files{$file} = 0 if $f =~ $_ }

    # system "pwd; ls -l '$file'";
    $Files{$file} = -e $file ? 1 : 0;
    warn __PACKAGE__ . qq(: Can't find file "$file" (@_): ignored.\n)
        unless $Files{$file} || $Silent || $file =~ /\(eval \d+\)/ ||
               $file eq "../../lib/Storable.pm" ||
               $file eq "../../lib/POSIX.pm";

    $Files{$file}
}

sub check_file
{
    my ($cv) = @_;

    return unless class($cv) eq "CV";

    my $op = $cv->START;
    return unless $op->can("file") && class($op) ne "NULL" && is_state($op);

    my $file = $op->file;
    my $use  = use_file($file);
    # printf STDERR "%6s $file\n", $use ? "use" : "ignore";

    $use
}

sub B::GV::find_cv
{
    my $cv = $_[0]->CV;
    return unless $$cv;

    # print STDERR "find_cv $$cv\n" if check_file($cv);
    push @Cvs, $cv if check_file($cv);
    push @Cvs, grep check_file($_), $cv->PADLIST->ARRAY->ARRAY
        if $cv->can("PADLIST") &&
           $cv->PADLIST->can("ARRAY") &&
           $cv->PADLIST->ARRAY &&
           $cv->PADLIST->ARRAY->can("ARRAY");
};

sub sub_info
{
    my ($cv) = @_;
    my ($name, $start) = ("", 0);
    if (!$cv->GV->isa("B::SPECIAL"))
    {
        return unless $cv->GV->can("SAFENAME");
        $name = $cv->GV->SAFENAME;
        # print STDERR "--[$name]--\n";
        $name =~ s/(__ANON__)\[.+:\d+\]/$1/ if defined $name;
    }
    my $root = $cv->ROOT;
    if ($root->can("first"))
    {
        my $lineseq = $root->first;
        if ($lineseq->can("first"))
        {
            # normal case
            $start = $lineseq->first;
        }
        elsif ($lineseq->name eq "nextstate")
        {
            # completely empty sub - sub empty { }
            $start = $lineseq;
        }
    }
    ($name, $start)
}

sub check_files
{
    # print STDERR "Checking files\n";

    @Cvs = grep check_file($_), B::main_cv->PADLIST->ARRAY->ARRAY;

    my %seen_pkg;
    my %seen_cv;

    walksymtable(\%main::, "find_cv", sub { !$seen_pkg{$_[0]}++ });

    my $l = sub
    {
        my ($cv) = @_;
        my $line = 0;
        my ($name, $start) = sub_info($cv);
        if ($start)
        {
            local ($Line, $File);
            get_location($start);
            $line = $Line;
            # print STDERR "$name - $File:$Line\n";
        }
        ($line, $name)
    };

    @Cvs = map  $_->[0],
           sort { $a->[1] <=> $b->[1] || $a->[2] cmp $b->[2] }
           map  [ $_, $l->($_) ],
           grep !$seen_cv{$$_}++,
           @Cvs;

    # Hack to bump up the refcount of the subs.  If we don't do this then the
    # subs in some modules don't seem to be around when we get to looking at
    # them.  I'm not sure why this is, and it seems to me that this hack could
    # affect the order of destruction, but I've not seen any problems.  Yet.
    # object_2svref doesn't exist before 5.8.1.
    @Subs = map $_->object_2svref, @Cvs if $] >= 5.008001;
}

sub report
{
    local @SIG{qw(__DIE__ __WARN__)};

    $Run{finish} = get_elapsed();

    die "Devel::Cover::import() not run: " .
        "did you require instead of use Devel::Cover?\n"
        unless defined $Dir;

    chdir $Dir or die __PACKAGE__ . ": Can't chdir $Dir: $!\n";

    my @collected = get_coverage();
    return unless @collected;
    set_coverage("none");

    $Run{collected} = \@collected;
    $Structure      = Devel::Cover::DB::Structure->new(base => $DB);
    $Structure->read_all;
    $Structure->add_criteria(@collected);
    # use Data::Dumper; $Data::Dumper::Indent = 1;
    # use Data::Dumper; print STDERR "Start structure: ", Dumper $Structure;

    # print STDERR "Processing cover data\n@Inc\n";
    $Coverage = coverage(1) || die "No coverage data available.\n";
    # use Data::Dumper; print STDERR Dumper $Coverage;

    check_files();

    unless ($Subs_only)
    {
        get_cover(main_cv, main_root);
        get_cover($_)
            for B::begin_av()->isa("B::AV") ? B::begin_av()->ARRAY : ();
        if (exists &B::check_av)
        {
            get_cover($_)
                for B::check_av()->isa("B::AV") ? B::check_av()->ARRAY : ();
        }
        # get_ends includes INIT blocks
        get_cover($_)
            for get_ends()->isa("B::AV") ? get_ends()->ARRAY : ();
    }
    # print STDERR "--- @Cvs\n";
    get_cover($_) for @Cvs;

    my %files;
    $files{$_}++ for keys %{$Run{count}}, keys %{$Run{vec}};
    for my $file (sort keys %files)
    {
        # print STDERR "looking at $file\n";
        unless (use_file($file))
        {
            # print STDERR "deleting $file\n";
            delete $Run{count}->{$file};
            delete $Run{vec}  ->{$file};
            $Structure->delete_file($file);
            next;
        }

        # $Structure->add_digest($file, \%Run);

        for my $run (keys %{$Run{vec}{$file}})
        {
            delete $Run{vec}{$file}{$run} unless $Run{vec}{$file}{$run}{size};
        }

        $Structure->store_counts($file);
    }

    # use Data::Dumper; print STDERR "End structure: ", Dumper $Structure;

    my $run = time . ".$$." . sprintf "%05d", rand 2 ** 16;
    my $cover = Devel::Cover::DB->new
    (
        base      => $DB,
        runs      => { $run => \%Run },
        structure => $Structure,
    );

    $DB .= "/runs";
    unless (-d $DB)
    {
        mkdir $DB, 0700 or croak "Can't mkdir $DB: $!\n";
        chmod 0700, $DB or croak "Can't chmod $DB: $!\n";
    }
    $DB .= "/$run";

    $cover->{db} = $DB;

    print OUT __PACKAGE__, ": Writing coverage database to $DB\n"
        unless $Silent;
    $cover->write;
    $cover->print_summary if $Summary && !$Silent;
}

sub add_subroutine_cover
{
    my ($op) = @_;

    get_location($op);
    return unless $File;

    # print STDERR "Subroutine $Sub_name $File:$Line: ", $op->name, "\n";

    my $key = get_key($op);
    my $val = $Coverage->{statement}{$key} || 0;
    my ($n, $new) = $Structure->add_count("subroutine");
    # print STDERR "******* subroutine $n - $new\n";
    $Structure->add_subroutine($File, [ $Line, $Sub_name ]) if $new;
    $Run{count}{$File}{subroutine}[$n] += $val;
    my $vec = $Run{vec}{$File}{subroutine};
    vec($vec->{vec}, $n, 1) = $val ? 1 : 0;
    $vec->{size} = $n + 1;
}

sub add_statement_cover
{
    my ($op) = @_;

    get_location($op);
    return unless $File;

    # print STDERR "Stmt $File:$Line: $op $$op ", $op->name, "\n";

    $Run{digests}{$File} ||= $Structure->set_file($File);
    my $key = get_key($op);
    my $val = $Coverage->{statement}{$key} || 0;
    my ($n, $new) = $Structure->add_count("statement");
    $Structure->add_statement($File, $Line) if $new;
    $Run{count}{$File}{statement}[$n] += $val;
    my $vec = $Run{vec}{$File}{statement};
    vec($vec->{vec}, $n, 1) = $val ? 1 : 0;
    $vec->{size} = $n + 1;
    no warnings "uninitialized";
    $Run{count}{$File}{time}[$n] += $Coverage->{time}{$key}
        if exists $Coverage->{time} && exists $Coverage->{time}{$key};
}

my %Seen;

sub add_branch_cover
{
    return unless $Collect && $Coverage{branch};

    my ($op, $type, $text, $file, $line) = @_;

    # return unless $Seen{branch}{$$op}++;

    $text =~ s/^\s+//;
    $text =~ s/\s+$//;

    my $key = get_key($op);
    my $c   = $Coverage->{condition}{$key};

    no warnings "uninitialized";
    # warn "add_branch_cover $File:$Line [$type][@{[join ', ', @$c]}]\n";

    if ($type eq "and" ||
        $type eq "or"  ||
        ($type eq "elsif" && !exists $Coverage->{branch}{$key}))
    {
        # and   => this could also be a plain if with no else or elsif
        # or    => this could also be an unless with no else or elsif
        # elsif => no subsequent elsifs or elses
        # True path taken if not short circuited.
        # False path taken if short circuited.
        $c = [ $c->[1] + $c->[2], $c->[3] ];
        # print STDERR "branch $type [@$c]\n";
    }
    else
    {
        $c = $Coverage->{branch}{$key} || [0, 0];
    }

    my ($n, $new) = $Structure->add_count("branch");
    $Structure->add_branch($file, [ $line, { text => $text } ]) if $new;
    my $ccount = $Run{count}{$file};
    if (exists $ccount->{branch}[$n])
    {
        $ccount->{branch}[$n][$_] += $c->[$_] for 0 .. $#$c;
    }
    else
    {
        $ccount->{branch}[$n] = $c;
        my $vec = $Run{vec}{$File}{branch};
        vec($vec->{vec}, $vec->{size}++, 1) = $_ ||= 0 ? 1 : 0 for @$c;
    }

    # warn "branch $type %x [@$c] => [@{$ccount->{branch}[$n]}]\n", $$op;
}

my %condition_locations;

sub add_condition_cover
{
    my ($op, $strop, $left, $right) = @_;

    unless ($Collect)
    {
        # $condition_locations{$$op} = [ $File, $Line ];
        return
    }

    # local ($File, $Line) = @{$condition_locations{$$op}}
        # if exists $condition_locations{$$op};

    my $key = get_key($op);
    # print STDERR "Condition cover $$op from $File:$Line\n";

    my $type = $op->name;
    $type =~ s/assign$//;
    $type = "or" if $type eq "dor";

    my $c = $Coverage->{condition}{$key};

    no warnings "uninitialized";

    my $count;

    if ($type eq "or" || $type eq "and")
    {
        my $r = $op->first->sibling;
        my $name = $r->name;
        $name = $r->first->name if $name eq "sassign";
        # TODO - exec?  any others?
        # print STDERR "Name [$name]\n";
        if ($c->[5] || $name =~
            /^const|s?refgen|gelem|die|undef|bless|anon(?:list|hash)|scalar$/)
        {
            $c = [ $c->[3], $c->[1] + $c->[2] ];
            $count = 2;
        }
        else
        {
            @$c = @{$c}[$type eq "or" ? (3, 2, 1) : (3, 1, 2)];
            $count = 3;
        }
        # print STDERR "$type 3 $name [@$c] $File:$Line\n";
    }
    elsif ($type eq "xor")
    {
        # !l&&!r  l&&!r  l&&r  !l&&r
        @$c = @{$c}[3, 2, 4, 1];
        $count = 4;
    }
    else
    {
        die qq(Unknown type "$type" for conditional);
    }

    my $structure =
    {
        type  => "${type}_${count}",
        op    => $strop,
        left  => $left,
        right => $right,
    };

    my ($n, $new) = $Structure->add_count("condition");
    $Structure->add_condition($File, [ $Line, $structure ]) if $new;
    my $ccount = $Run{count}{$File};
    if (exists $ccount->{condition}[$n])
    {
        $ccount->{condition}[$n][$_] += $c->[$_] for 0 .. $#$c;
    }
    else
    {
        $ccount->{condition}[$n] = $c;
        my $vec = $Run{vec}{$File}{condition};
        vec($vec->{vec}, $vec->{size}++, 1) = $_ ||= 0 ? 1 : 0 for @$c;
    }
}

*is_scope       = \&B::Deparse::is_scope;
*is_state       = \&B::Deparse::is_state;
*is_ifelse_cont = \&B::Deparse::is_ifelse_cont;

{

my %Original;
BEGIN
{
    $Original{deparse}     = \&B::Deparse::deparse;
    $Original{logop}       = \&B::Deparse::logop;
    $Original{logassignop} = \&B::Deparse::logassignop;
}

sub deparse
{
    my $self = shift;
    my ($op, $cx) = @_;

    my $deparse;

    if ($Collect)
    {
        my $class = class($op);
        my $null  = $class eq "NULL";

        my $name = $op->can("name") ? $op->name : "Unknown";

        # print STDERR "$class:$name at $File:$Line\n";

        {
            # Collect everything under here.
            local ($File, $Line) = ($File, $Line);
            $deparse = eval { $Original{deparse}->($self, @_) };
            $deparse =~ s/^\010+//mg if defined $deparse;
            $deparse = "Deparse error: $@" if $@;
            # print STDERR "Collect Deparse $op $$op => <$deparse>\n";
        }

        # Get the coverage on this op.

        if ($class eq "COP" && $Coverage{statement})
        {
            add_statement_cover($op) unless $Seen{statement}{$$op}++;
        }
        elsif (!$null && $name eq "null"
                      && ppname($op->targ) eq "pp_nextstate"
                      && $Coverage{statement})
        {
            # If the current op is null, but it was nextstate, we can still
            # get at the file and line number, but we need to get dirty.

            bless $op, "B::COP";
            add_statement_cover($op) unless $Seen{statement}{$$op}++;
            bless $op, "B::$class";
        }
        elsif ($Seen{other}{$$op}++)
        {
            return ""  # Only report on each op once.
        }
        elsif ($name eq "cond_expr")
        {
            local ($File, $Line) = ($File, $Line);
            my $cond  = $op->first;
            my $true  = $cond->sibling;
            my $false = $true->sibling;
            if (!($cx < 1 && (is_scope($true) && $true->name ne "null") &&
                    (is_scope($false) || is_ifelse_cont($false))
                    && $self->{'expand'} < 7))
            {
                { local $Collect; $cond = $self->deparse($cond, 8) }
                add_branch_cover($op, "if", "$cond ? :", $File, $Line);
            }
            else
            {
                { local $Collect; $cond = $self->deparse($cond, 1) }
                add_branch_cover($op, "if", "if ($cond) { }", $File, $Line);
                while (class($false) ne "NULL" && is_ifelse_cont($false))
                {
                    my $newop   = $false->first;
                    my $newcond = $newop->first;
                    my $newtrue = $newcond->sibling;
                    if ($newcond->name eq "lineseq")
                    {
                        # lineseq to ensure correct line numbers in elsif()
                        # Bug #37302 fixed by change #33710.
                        $newcond = $newcond->first->sibling;
                    }
                    # last in chain is OP_AND => no else
                    $false      = $newtrue->sibling;
                    { local $Collect; $newcond = $self->deparse($newcond, 1) }
                    add_branch_cover($newop, "elsif", "elsif ($newcond) { }",
                                     $File, $Line);
                }
            }
        }
    }
    else
    {
        local ($File, $Line) = ($File, $Line);
        $deparse = eval { $Original{deparse}->($self, @_) };
        $deparse =~ s/^\010+//mg if defined $deparse;
        $deparse = "Deparse error: $@" if $@;
        # print STDERR "Deparse => <$deparse>\n";
    }

    $deparse
}

sub logop
{
    my $self = shift;
    my ($op, $cx, $lowop, $lowprec, $highop, $highprec, $blockname) = @_;
    my $left  = $op->first;
    my $right = $op->first->sibling;
    my ($file, $line) = ($File, $Line);
    if ($cx < 1 && is_scope($right) && $blockname && $self->{expand} < 7)
    {
        # if ($a) {$b}
        {
            # local $Collect;
            $left  = $self->deparse($left,  1);
            $right = $self->deparse($right, 0);
        }
        add_branch_cover($op, $lowop, "$blockname ($left)", $file, $line)
            unless $Seen{branch}{$$op}++;
        return "$blockname ($left) {\n\t$right\n\b}\cK"
    }
    elsif ($cx < 1 && $blockname && !$self->{parens} && $self->{expand} < 7)
    {
        # $b if $a
        {
            # local $Collect;
            $right = $self->deparse($right, 1);
            $left  = $self->deparse($left,  1);
        }
        add_branch_cover($op, $lowop, "$blockname $left", $file, $line)
            unless $Seen{branch}{$$op}++;
        return "$right $blockname $left"
    }
    elsif ($cx > $lowprec && $highop)
    {
        # $a && $b
        {
            # local $Collect;
            $left  = $self->deparse_binop_left ($op, $left,  $highprec);
            $right = $self->deparse_binop_right($op, $right, $highprec);
        }
        add_condition_cover($op, $highop, $left, $right)
            unless $Seen{condition}{$$op}++;
        return $self->maybe_parens("$left $highop $right", $cx, $highprec)
    }
    else
    {
        # $a and $b
        {
            # local $Collect;
            $left  = $self->deparse_binop_left ($op, $left,  $lowprec);
            $right = $self->deparse_binop_right($op, $right, $lowprec);
        }
        add_condition_cover($op, $lowop, $left, $right)
            unless $Seen{condition}{$$op}++;
        return $self->maybe_parens("$left $lowop $right", $cx, $lowprec)
    }
}

sub logassignop
{
    my $self = shift;
    my ($op, $cx, $opname) = @_;
    my $left = $op->first;
    my $right = $op->first->sibling->first;  # skip sassign
    $left = $self->deparse($left, 7);
    $right = $self->deparse($right, 7);
    add_condition_cover($op, $opname, $left, $right);
    return $self->maybe_parens("$left $opname $right", $cx, 7);
}

}

sub get_cover
{
    my $deparse = B::Deparse->new;

    my $cv = $deparse->{curcv} = shift;

    ($Sub_name, my $start) = sub_info($cv);

    # print STDERR "get_cover: <$Sub_name>\n";
    return unless defined $Sub_name;  # Only happens within Safe.pm, AFAIK.

    get_location($start) if $start;
    # print STDERR "[[$File:$Line]]\n";
    # return unless length $File;
    return if length $File && !use_file($File);

    # printf STDERR "getting cover for $Sub_name ($start), %x\n", $$cv;

    if ($start)
    {
        no warnings "uninitialized";
        if ($File eq $Structure->get_file && $Line == $Structure->get_line &&
            $Sub_name eq "__ANON__" && $Structure->get_sub_name eq "__ANON__")
        {
            # Merge instances of anonymous subs into one.
            # TODO - multiple anonymous subs on the same line.
        }
        else
        {
            my $count = $Sub_count->{$File}{$Line}{$Sub_name}++;
            $Structure->set_subroutine($Sub_name, $File, $Line, $count);
            add_subroutine_cover($start)
                if $Coverage{subroutine} || $Coverage{pod};  # pod requires subs
        }
    }

    if ($Pod && $Coverage{pod})
    {
        unless ($cv->GV->isa("B::SPECIAL"))
        {
            my $stash = $cv->GV->STASH;
            my $pkg   = $stash->NAME;
            my $file  = $cv->FILE;
            my %opts;
            $Run{digests}{$File} ||= $Structure->set_file($File);
            if (ref $Coverage_options{pod})
            {
                my $p;
                for (@{$Coverage_options{pod}})
                {
                    if (/^package|private|also_private|trust_me|pod_from|nocp$/)
                    {
                        $opts{$p = $_} = [];
                    }
                    elsif ($p)
                    {
                        push @{$opts{$p}}, $_;
                    }
                }
                for $p (qw( private also_private trust_me ))
                {
                    next unless exists $opts{$p};
                    $_ = qr/$_/ for @{$opts{$p}};
                }
            }
            $Pod = "Pod::Coverage" if delete $opts{nocp};
            # use Data::Dumper; print STDERR "$Pod, ", Dumper \%opts;
            if ($Pod{$file} ||= $Pod->new(package => $pkg, %opts))
            {
                my $covered;
                for ($Pod{$file}->covered)
                {
                    $covered = 1, last if $_ eq $Sub_name;
                }
                unless ($covered)
                {
                    for ($Pod{$file}->uncovered)
                    {
                        $covered = 0, last if $_ eq $Sub_name;
                    }
                }
                if (defined $covered)
                {
                    my ($n, $new) = $Structure->add_count("pod");
                    $Structure->add_pod($File, [ $Line, $Sub_name ]) if $new;
                    $Run{count}{$File}{pod}[$n] += $covered;
                    my $vec = $Run{vec}{$File}{pod};
                    vec($vec->{vec}, $n, 1) = $covered ? 1 : 0;
                    $vec->{size} = $n + 1;
                }
            }
        }
    }

    # my $dd = @_ && ref $_[0]
                 # ? $deparse->deparse($_[0], 0)
                 # : $deparse->deparse_sub($cv, 0);
    # print STDERR "get_cover: <$Sub_name>\n";
    # print STDERR "[[$File:$Line]]\n";
    # print STDERR "<$dd>\n";

    no warnings "redefine";
    local *B::Deparse::deparse     = \&deparse;
    local *B::Deparse::logop       = \&logop;
    local *B::Deparse::logassignop = \&logassignop;

    my $de = @_ && ref $_[0]
                 ? $deparse->deparse($_[0], 0)
                 : $deparse->deparse_sub($cv, 0);
    # print STDERR "<$de>\n";
    $de
}

bootstrap Devel::Cover $VERSION;

1

__END__

=head1 NAME

Devel::Cover - Code coverage metrics for Perl

=head1 SYNOPSIS

To get coverage for an uninstalled module:

 cover -test

or

 cover -delete
 HARNESS_PERL_SWITCHES=-MDevel::Cover make test
 cover

To get coverage for an uninstalled module which uses Module::Build (0.26 or
later):

 ./Build testcover

If the module does not use the t/*.t framework:

 PERL5OPT=-MDevel::Cover make test

If you want to get coverage for a program:

 perl -MDevel::Cover yourprog args
 cover

 perl -MDevel::Cover=-db,cover_db,-coverage,statement,time yourprog args

=head1 DESCRIPTION

This module provides code coverage metrics for Perl. Code coverage
metrics describe how thoroughly tests exercise code. By using
Devel::Cover you can discover areas of code not exercised by your tests
and determine which tests to create to increase coverage. Code coverage
can be considered as an indirect measure of quality.

I consider this software to have an alpha status.  By that I mean that I
reserve the right to alter the interface in a backwards incompatible manner
without incrementing the major version number.  I specifically do not mean
that this software is full of bugs or missing key features.  Although I'm
making no guarantees on that front either.  In short, if you are looking for
code coverage software for Perl, you have probably come to the end of your
search.  For more of my opinions on this subject, see
http://pjcj.sytes.net/notes/2007/03/14#alpha

Code coverage data are collected using a pluggable runops function which
counts how many times each op is executed.  These data are then mapped
back to reality using the B compiler modules.  There is also a statement
profiling facility which needs a better backend to be really useful.
This release also includes an experimental mode which replaces ops
instead of using a pluggable runops function.  This provides a nice
speed increase, but needs better testing before it becomes the default.
You probably don't care about any of this.

The F<cover> program can be used to generate coverage reports.

Statement, branch, condition, subroutine, pod and time coverage information is
reported.  Statement coverage data should be reasonable, although there may be
some statements which are not reported.  Branch and condition coverage data
should be mostly accurate too, although not always what one might initially
expect.  Subroutine coverage should be as accurate as statement coverage.  Pod
coverage comes from L<Pod::Coverage>.  If L<Pod::Coverage::CountParents> is
available it will be used instead.  Coverage data for path coverage are not yet
collected.

The F<gcov2perl> program can be used to convert gcov files to
C<Devel::Cover> databases.

You may find that the results don't match your expectations.  I would
imagine that at least one of them is wrong.

The most appropriate mailing list on which to discuss this module would
be perl-qa.  Discussion has migrated there from perl-qa-metrics which is
now defunct.  See L<http://lists.perl.org/showlist.cgi?name=perl-qa>.

=head1 REQUIREMENTS

=over

=item * Perl 5.6.1 or greater.  Perl 5.8.2 or greater is recommended.

Perl 5.7.0 is unsupported.  Perl 5.8.2 or greater is recommended.
Whilst Perl 5.6 should mostly work you will probably miss out on
coverage information which would be available using a more modern
version and will likely run into bugs in perl.  Perl 5.8.0 will give
slightly different results to more recent versions due to changes in the
op tree.

=item * The ability to compile XS extensions.

This means a working compiler and make program at least.

=item * L<Storable> and L<Digest::MD5>

Both are in the core in Perl 5.8.0 and above.

=item * L<Template> and L<PPI::HTML> or L<Perl::Tidy>

if you want syntax highlighted HTML reports.

=item * L<Pod::Coverage>

if you want Pod coverage.

=item * L<Test::Differences>

if the tests fail and you would like nice output telling you why.

=back

=head1 OPTIONS

 -blib               - "use blib" and ignore files matching \bt/ (default true
                       iff blib directory exists).
 -coverage criterion - Turn on coverage for the specified criterion.  Criteria
                       include statement, branch, condition, path, subroutine,
                       pod, time, all and none (default all available).
 -db cover_db        - Store results in coverage db (default ./cover_db).
 -dir path           - Directory in which coverage will be collected (default
                       cwd).
 -ignore RE          - Set REs of files to ignore (default "/Devel/Cover\b").
 +ignore RE          - Append to REs of files to ignore.
 -inc path           - Set prefixes of files to ignore (default @INC).
 +inc path           - Append to prefixes of files to ignore.
 -merge val          - Merge databases, for multiple test benches (default on).
 -select RE          - Set REs of files to select (default none).
 +select RE          - Append to REs of files to select.
 -silent val         - Don't print informational messages (default off)
 -subs_only val      - Only cover code in subroutine bodies (default off)
 -summary val        - Print summary information iff val is true (default on).

=head2 More on Coverage Options

You can specify options to some coverage criteria.  At the moment only pod
coverage takes any options.  These are the parameters which are passed into the
Pod::Coverage constructor.  The extra options are separated by dashes, and you
may specify as many as you wish.  For example, to specify that all subroutines
containing xx are private, call Devel::Cover with the option
-coverage,pod-also_private-xx.

=head1 SELECTING FILES TO COVER

You may select which files you want covered using the select, ignore and inc
options.  The system works as follows:

Any file matching a RE given as a select option is selected.

Otherwise, any file matching a RE given as an ignore option is ignored.

Otherwise, any file in one of the inc directories is ignored.

Otherwise the file is selected.

You may add to the REs to select by using +select, or you may reset the
selections using -select.  The same principle applies to the REs to
ignore.

The inc directories are initially populated with the contents of the
@INC array at the time Devel::Cover was built.  You may reset these
directories using -inc, or add to them using +inc.

Although these options take regular expressions, you should not enclose the RE
within // or any other quoting characters.

=head1 ENVIRONMENT

The -silent option is turned on when Devel::Cover is invoked via
$HARNESS_PERL_SWITCHES or $PERL5OPT.  Devel::Cover tries to do the right
thing when $MOD_PERL is set.  $DEVEL_COVER_OPTIONS is appended to any
options passed into Devel::Cover.

When running Devel::Cover's own test suite, $DEVEL_COVER_DEBUG turns on
debugging information, $DEVEL_COVER_GOLDEN_VERSION overrides
Devel::Cover's own idea of which golden results it should test against,
and $DEVEL_COVER_NO_COVERAGE runs the tests without collecting coverage.

=head1 ACKNOWLEDGEMENTS

Some code and ideas cribbed from:

 Devel::OpProf
 B::Concise
 B::Deparse

=head1 SEE ALSO

 Devel::Cover::Tutorial
 B
 Pod::Coverage

=head1 LIMITATIONS

There are things that Devel::Cover can't cover.

=head2 Absence of shared dependencies

Perl keeps track of which modules have been loaded (to avoid reloading
them).  Because of this, it isn't possible to get coverage for a path
where a runtime import fails if the module being imported is one that
Devel::Cover uses internally.  For example, suppose your program has
this function:

 sub foo {
     eval { require Storable };
     if ($@) {
         carp "Can't find Storable";
         return;
     }
     # ...
 }

You might write a test for the failure mode as

 BEGIN { @INC = () }
 foo();
 # check for error message

Because Devel::Cover uses Storable internally, the import will succeed
(and the test will fail) under a coverage run.

Modules used by Devel::Cover while gathering coverage:

=over 4

=item * B

=item * B::Debug

=item * B::Deparse

=item * Carp

=item * Cwd

=item * Digest::MD5

=item * File::Path

=item * File::Spec

=item * Storable

=back

=head2 mod_perl

By adding C<use Devel::Cover;> to your mod_perl startup script, you
should be able to collect coverage information when running under
mod_perl.  You can also add any options you need at this point.  I would
suggest adding this as early as possible in your startup script in order
to collect as much coverage information as possible.

=head2 Redefined subroutines

If you redefine a subroutine you may find that the original subroutine is not
reported on.  This is because I haven't yet found a way to locate the original
CV.  Hints, tips or patches to resolve this will be gladly accepted.

=head1 BUGS

Almost certainly.

See the BUGS file.  And the TODO file.

=head1 VERSION

Version 0.64 - 10th April 2008

=head1 LICENCE

Copyright 2001-2008, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

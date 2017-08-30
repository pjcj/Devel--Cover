# Copyright 2001-2017, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover;

use strict;
use warnings;

our $VERSION;
BEGIN {
# VERSION
}

use DynaLoader ();
our @ISA = "DynaLoader";

# sub Pod::Coverage::TRACE_ALL () { 1 }

use Devel::Cover::DB;
use Devel::Cover::DB::Digests;
use Devel::Cover::Inc;

BEGIN { $VERSION //= $Devel::Cover::Inc::VERSION }

use B qw( class ppname main_cv main_start main_root walksymtable OPf_KIDS );
use B::Debug;
use B::Deparse;

use Carp;
use Config;
use Cwd qw( abs_path getcwd );
use File::Spec;

use Devel::Cover::Dumper;
use Devel::Cover::Util "remove_contained_paths";

BEGIN {
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
my $DB             = "cover_db";         # DB name.
my $Merge          = 1;                  # Merge databases.
my $Summary        = 1;                  # Output coverage summary.
my $Subs_only      = 0;                  # Coverage only for sub bodies.
my $Self_cover_run = 0;                  # Covering Devel::Cover now.
my $Loose_perms    = 0;                  # Use loose permissions in the cover DB

my @Ignore;                              # Packages to ignore.
my @Inc;                                 # Original @INC to ignore.
my @Select;                              # Packages to select.
my @Ignore_re;                           # Packages to ignore.
my @Inc_re;                              # Original @INC to ignore.
my @Select_re;                           # Packages to select.

my $Pod = $INC{"Pod/Coverage/CountParents.pm"} ? "Pod::Coverage::CountParents"
        : $INC{"Pod/Coverage.pm"}              ? "Pod::Coverage"
        : "";                            # Type of pod coverage available.
my %Pod;                                 # Pod coverage data.

my @Cvs;                                 # All the Cvs we want to cover.
my %Cvs;                                 # All the Cvs we want to cover.
my @Subs;                                # All the subs we want to cover.
my $Cv;                                  # Cv we are looking in.
my $Sub_name;                            # Name of the sub we are looking in.
my $Sub_count;                           # Count for multiple subs on same line.

my $Coverage;                            # Raw coverage data.
my $Structure;                           # Structure of the files.
my $Digests;                             # Digests of the files.

my %Criteria;                            # Names of coverage criteria.
my %Coverage;                            # Coverage criteria to collect.
my %Coverage_options;                    # Options for overage criteria.

my %Run;                                 # Data collected from the run.

my $Const_right = qr/^(?:const|s?refgen|gelem|die|undef|bless|anon(?:list|hash)|
                       scalar|return|last|next|redo|goto)$/x;
                                         # constant ops

use vars '$File',                        # Last filename we saw.  (localised)
         '$Line',                        # Last line number we saw.  (localised)
         '$Collect',                     # Whether or not we are collecting
                                         # coverage data.  We make two passes
                                         # over conditions.  (localised)
         '%Files',                       # Whether we are interested in files.
                                         # Used in runops function.
         '$Replace_ops',                 # Whether we are replacing ops.
         '$Silent',                      # Output nothing. Can be used anywhere.
         '$Self_cover';                  # Coverage of Devel::Cover.

BEGIN {
    ($File, $Line, $Collect) = ("", 0, 1);
    $Silent = ($ENV{HARNESS_PERL_SWITCHES} || "") =~ /Devel::Cover/ ||
              ($ENV{PERL5OPT}              || "") =~ /Devel::Cover/;
    *OUT = $ENV{DEVEL_COVER_DEBUG} ? *STDERR : *STDOUT;

    if ($] < 5.010000 && !$ENV{DEVEL_COVER_UNSUPPORTED}) {
        my $v = $] < 5.008001 ? "1.22" : "1.23";
        print <<EOM;

================================================================================

                                   IMPORTANT
                                   ---------

Devel::Cover $VERSION is not supported on perl $].  The last version of
Devel::Cover which was supported was version $v.  This version may not work.
I have not tested it.  If it does work it will not be fully functional.

If you decide to use it anyway, you are on your own.  If it works at all, there
will be some constructs for which coverage will not be collected, and you may
well encounter bugs which have been fixed in subsequent versions of perl.
EOM

        print <<EOM if $^O eq "MSWin32";

And things are even worse under Windows.  You may well find random bugs of
various severities.
EOM
        print <<EOM;

If you are actually using this version of Devel::Cover with perl $], please let
me know.  I don't want to know if you are just testing Devel::Cover, only if you
are seriously using this version to do code coverage analysis of real code.  If
I get no reports of such usage then I will remove support and delete the
workarounds for versions of perl below 5.10.0.

In order to use this version of Devel::Cover with perl $] you must set the
environment variable \$DEVEL_COVER_UNSUPPORTED

================================================================================

EOM

        die "Exiting";
    }

    if ($^X =~ /(apache2|httpd)$/) {
        # mod_perl < 2.0.8
        @Inc = @Devel::Cover::Inc::Inc;
    } else {
        # Can't get @INC via eval `` in taint mode, revert to default value.
        if (${^TAINT}) {
            @Inc = @Devel::Cover::Inc::Inc;
        } else {
            eval {
                local %ENV = %ENV;
                # Clear *PERL* variables, but keep PERL5?LIB for local::lib
                # environments
                /perl/i and !/^PERL5?LIB$/ and delete $ENV{$_} for keys %ENV;
                my $cmd = "$^X -MData::Dumper -e " . '"print Dumper \@INC"';
                my $VAR1;
                # print STDERR "Running [$cmd]\n";
                eval `$cmd`;
                @Inc = @$VAR1;
            };
            if ($@) {
                print STDERR __PACKAGE__,
                             ": Error getting \@INC: $@\n",
                             "Reverting to default value for Inc.\n";
                @Inc = @Devel::Cover::Inc::Inc;
            }
        }
    }

    @Inc = map { -d $_ ? ($_ eq "." ? $_ : Cwd::abs_path($_)) : () } @Inc;

    @Inc = remove_contained_paths(getcwd, @Inc);

    @Ignore = ("/Devel/Cover[./]") unless $Self_cover = $ENV{DEVEL_COVER_SELF};
    # $^P = 0x004 | 0x010 | 0x100 | 0x200;
    # $^P = 0x004 | 0x100 | 0x200;
    $^P |= 0x004 | 0x100;
}

sub version { $VERSION }

if (0 && $Config{useithreads}) {
    eval "use threads";

    no warnings "redefine";

    my $original_join;
    BEGIN { $original_join = \&threads::join }
    # print STDERR "original_join: $original_join\n";

    # $original_join = sub { print STDERR "j\n" };

    # sub threads::join
    *threads::join = sub {
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

    *threads::DESTROY = sub {
        my $self = shift;
        print STDERR "(destroying thread ", $self->tid, ")\n";
        $original_destroy->($self, @_);
    };

    # print STDERR "threads::join: ", \&threads::join, "\n";

    my $new = \&threads::new;
    *threads::new = *threads::create = sub {
        my $class     = shift;
        my $sub       = shift;
        my $wantarray = wantarray;

        $new->($class,
               sub {
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

{
    sub check {
        return unless $Initialised;

        check_files();

        set_coverage(keys %Coverage);
        my @coverage = get_coverage();
        %Coverage = map { $_ => 1 } @coverage;

        delete $Coverage{path};  # not done yet
        my $nopod = "";
        if (!$Pod && exists $Coverage{pod}) {
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

        populate_run();
    }

    no warnings "void";  # avoid "Too late to run CHECK block" warning
    CHECK { check }
}

{
    my $run_end = 0;
    sub first_end {
        # print STDERR "**** END 1 - $run_end\n";
        set_last_end() unless $run_end++
    }

    my $run_init = 0;
    sub first_init {
        # print STDERR "**** INIT 1 - $run_init\n";
        collect_inits() unless $run_init++
    }
}

sub last_end {
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

sub CLONE {
    print STDERR <<EOM;

Unfortunately, Devel::Cover does not yet work with threads.  I have done
some work in this area, but there is still more to be done.

EOM
    require POSIX;
    POSIX::_exit(1);
}

$Replace_ops = !$Self_cover;

sub import {
    return if $Initialised;

    my $class = shift;

    # Die tainting.
    # Anyone using this module can do worse things than messing with tainting.
    my $options = ($ENV{DEVEL_COVER_OPTIONS} || "") =~ /(.*)/ ? $1 : "";
    my @o = (@_, split ",", $options);
    defined or $_ = "" for @o;
    # print STDERR __PACKAGE__, ": Parsing options from [@o]\n";

    my $blib = -d "blib";
    @Inc     = () if "@o" =~ /-inc /;
    @Ignore  = () if "@o" =~ /-ignore /;
    @Select  = () if "@o" =~ /-select /;
    while (@o)
    {
        local $_ = shift @o;
        /^-silent/      && do { $Silent      = shift @o; next };
        /^-dir/         && do { $Dir         = shift @o; next };
        /^-db/          && do { $DB          = shift @o; next };
        /^-loose_perms/ && do { $Loose_perms = shift @o; next };
        /^-merge/       && do { $Merge       = shift @o; next };
        /^-summary/     && do { $Summary     = shift @o; next };
        /^-blib/        && do { $blib        = shift @o; next };
        /^-subs_only/   && do { $Subs_only   = shift @o; next };
        /^-replace_ops/ && do { $Replace_ops = shift @o; next };
        /^-coverage/    &&
            do { $Coverage{+shift @o} = 1 while @o && $o[0] !~ /^[-+]/; next };
        /^[-+]ignore/   &&
            do { push @Ignore,   shift @o while @o && $o[0] !~ /^[-+]/; next };
        /^[-+]inc/      &&
            do { push @Inc,      shift @o while @o && $o[0] !~ /^[-+]/; next };
        /^[-+]select/   &&
            do { push @Select,   shift @o while @o && $o[0] !~ /^[-+]/; next };
        warn __PACKAGE__ . ": Unknown option $_ ignored\n";
    }

    if ($blib) {
        eval "use blib";
        for (@INC) { $_ = $1 if /(.*)/ }  # Die tainting.
        push @Ignore, "^t/", '\\.t$', '^test\\.pl$';
    }

    my $ci     = $^O eq "MSWin32";
    @Select_re = map qr/$_/,                           @Select;
    @Ignore_re = map qr/$_/,                           @Ignore;
    @Inc_re    = map $ci ? qr/^\Q$_\//i : qr/^\Q$_\//, @Inc;

    bootstrap Devel::Cover $VERSION;

    if (defined $Dir) {
        $Dir = $1 if $Dir =~ /(.*)/;  # Die tainting.
        chdir $Dir or die __PACKAGE__ . ": Can't chdir $Dir: $!\n";
    } else {
        $Dir = $1 if Cwd::getcwd() =~ /(.*)/;
    }

    unless (mkdir $DB) {
        die "Can't mkdir $DB: $!" unless -d $DB;
    }
    chmod 0777, $DB if $Loose_perms;
    $DB = $1 if abs_path($DB) =~ /(.*)/;
    Devel::Cover::DB->delete($DB) unless $Merge;

    %Files = ();  # start gathering file information from scratch

    for my $c (Devel::Cover::DB->new->criteria) {
        my $func = "coverage_$c";
        no strict "refs";
        $Criteria{$c} = $func->();
    }

    for (keys %Coverage) {
        my @c = split /-/, $_;
        if (@c > 1) {
            $Coverage{shift @c} = \@c;
            delete $Coverage{$_};
        }
        delete $Coverage{$_} unless length;
    }
    %Coverage = (all => 1) unless keys %Coverage;
    # print STDERR "Coverage: ", Dumper \%Coverage;
    %Coverage_options = %Coverage;

    $Initialised = 1;

    if ($ENV{MOD_PERL}) {
        eval "BEGIN {}";
        check();
        set_first_init_and_end();
    }
}

sub populate_run {
    my $self = shift;

    $Run{OS}      = $^O;
    $Run{perl}    = $] < 5.010 ? join ".", map ord, split //, $^V
                               : sprintf "%vd", $^V;
    $Run{dir}     = $Dir;
    $Run{run}     = $0;
    $Run{name}    = $Dir;
    $Run{version} = "unknown";

    my $mymeta = "$Dir/MYMETA.json";
    if (-e $mymeta) {
        eval {
            require Devel::Cover::DB::IO::JSON;
            my $io   = Devel::Cover::DB::IO::JSON->new;
            my $json = $io->read($mymeta);
            $Run{$_} = $json->{$_} for qw( name version abstract );
        }
    } elsif ($Dir =~ m|.*/([^/]+)$|) {
        my $filename = $1;
        eval {
            require CPAN::DistnameInfo;
            my $dinfo     = CPAN::DistnameInfo->new($filename);
            $Run{name}    = $dinfo->dist;
            $Run{version} = $dinfo->version;
        }
    }

    $Run{start} = get_elapsed() / 1e6;
}

sub cover_names_to_val
{
    my $val = 0;
    for my $c (@_) {
        if (exists $Criteria{$c}) {
            $val |= $Criteria{$c};
        } elsif ($c eq "all" || $c eq "none") {
            my $func = "coverage_$c";
            no strict "refs";
            $val |= $func->();
        } else {
            warn __PACKAGE__ . qq(: Unknown coverage criterion "$c" ignored.\n);
        }
    }
    $val;
}

sub set_coverage    { set_criteria(cover_names_to_val(@_))    }
sub add_coverage    { add_criteria(cover_names_to_val(@_))    }
sub remove_coverage { remove_criteria(cover_names_to_val(@_)) }

sub get_coverage {
    return unless defined wantarray;
    my @names;
    my $val = get_criteria();
    for my $c (sort keys %Criteria) {
        push @names, $c if $val & $Criteria{$c};
    }
    return wantarray ? @names : "@names";
}

{

my %File_cache;

# Recursion in normalised_file() is bad.  It can happen if a call from the sub
# evals something which wants to load a new module.  This has happened with
# the Storable backend.  I don't think it happens with the JSON backend.
my $Normalising;

sub normalised_file {
    my ($file) = @_;

    return $File_cache{$file} if exists $File_cache{$file};
    return $file if $Normalising;
    $Normalising = 1;

    my $f = $file;
    $file =~ s/ \(autosplit into .*\)$//;
    $file =~ s/^\(eval in .*\) //;
    # print STDERR "file is <$file>\ncoverage: ", Dumper coverage(0);
    if (exists coverage(0)->{module} && exists coverage(0)->{module}{$file} &&
        !File::Spec->file_name_is_absolute($file)) {
        my $m = coverage(0)->{module}{$file};
        # print STDERR "Loaded <$file> <$m->[0]> from <$m->[1]> ";
        $file = File::Spec->rel2abs($file, $m->[1]);
        # print STDERR "as <$file> ";
    }
    if ($] >= 5.008) {
        my $inc;
        $inc ||= $file =~ $_ for @Inc_re;
        # warn "inc for [$file] is [$inc] @Inc_re";
        if ($inc && ($^O eq "MSWin32" || $^O eq "cygwin")) {
            # Windows' Cwd::_win32_cwd() calls eval which will recurse back
            # here if we call abs_path, so we just assume it's normalised.
            # warn "giving up on getting normalised filename from <$file>\n";
        } else {
            # print STDERR "getting abs_path <$file> ";
            if (-e $file) {  # Windows likes the file to exist
                my $abs;
                $abs = abs_path($file) unless -l $file;  # leave symbolic links
                # print STDERR "giving <$abs> ";
                $file = $abs if defined $abs;
            }
        }
        # print STDERR "finally <$file> <$Dir>\n";
    }
    $file =~ s|\\|/|g if $^O eq "MSWin32";
    $file =~ s|^\Q$Dir\E/|| if defined $Dir;

    $Digests ||= Devel::Cover::DB::Digests->new(db => $DB);
    $file = $Digests->canonical_file($file);

    # print STDERR "File: $f => $file\n";

    $Normalising = 0;
    $File_cache{$f} = $file
}

}

sub get_location {
    my ($op) = @_;

    # print STDERR "get_location ", $op, "\n";
    # use Carp "cluck"; cluck("from here");
    return unless $op->can("file");  # How does this happen?
    $File = $op->file;
    $Line = $op->line;
    # print STDERR "$File:$Line\n";

    # If there's an eval, get the real filename.  Enabled from $^P & 0x100.
    while ($File =~ /^\(eval \d+\)\[(.*):(\d+)\]/) {
        ($File, $Line) = ($1, $2);
    }
    $File = normalised_file($File);

    if (!exists $Run{vec}{$File} && $Run{collected}) {
        my %vec;
        @vec{@{$Run{collected}}} = ();
        delete $vec{time};
        $vec{subroutine}++ if exists $vec{pod};
        @{$Run{vec}{$File}{$_}}{"vec", "size"} = ("", 0) for keys %vec;
    }
}

my $find_filename = qr/
  (?:^\(eval\s \d+\)\[(.+):\d+\])      |
  (?:^\(eval\sin\s\w+\)\s(.+))         |
  (?:\(defined\sat\s(.+)\sline\s\d+\)) |
  (?:\[from\s(.+)\sline\s\d+\])
/x;

sub use_file {
    # If we're in global destruction, forget it.
    return unless $find_filename;

    my ($file) = @_;

    # print STDERR "use_file($file)\n";

    # die "bad file" unless length $file;

    # If you call your file something that matches $find_filename then things
    # might go awry.  But it would be silly to do that, so don't.  This little
    # optimisation provides a reasonable speedup.
    return $Files{$file} if exists $Files{$file};

    # just don't call your filenames 0
    while ($file =~ $find_filename) { $file = $1 || $2 || $3 || $4 }
    $file =~ s/ \(autosplit into .*\)$//;

    # print STDERR "==> use_file($file)\n";

    return $Files{$file} if exists $Files{$file};
    return 0 if $file =~ /\(eval \d+\)/ ||
                $file =~ /^\.\.[\/\\]\.\.[\/\\]lib[\/\\](?:Storable|POSIX).pm$/;

    my $f = normalised_file($file);

    # print STDERR "checking <$file> <$f>\n";
    # print STDERR "checking <$file> <$f> against ",
                 # "select(@Select_re), ignore(@Ignore_re), inc(@Inc_re)\n";

    for (@Select_re) { return $Files{$file} = 1 if $f =~ $_ }
    for (@Ignore_re) { return $Files{$file} = 0 if $f =~ $_ }
    for (@Inc_re)    { return $Files{$file} = 0 if $f =~ $_ }

    # system "pwd; ls -l '$file'";
    $Files{$file} = -e $file ? 1 : 0;
    print STDERR __PACKAGE__ . qq(: Can't find file "$file" (@_): ignored.\n)
        unless $Files{$file} || $Silent
                             || $file =~ $Devel::Cover::DB::Ignore_filenames;

    add_cvs();  # add CVs now in case of symbol table manipulation
    $Files{$file}
}

sub check_file {
    my ($cv) = @_;

    return unless ref($cv) eq "B::CV";

    my $op = $cv->START;
    return unless ref($op) eq "B::COP";

    my $file = $op->file;
    my $use  = use_file($file);
    # printf STDERR "%6s $file\n", $use ? "use" : "ignore";

    $use
}

sub B::GV::find_cv {
    my $cv = $_[0]->CV;
    return unless $$cv;

    # print STDERR "find_cv $$cv\n" if check_file($cv);
    $Cvs{$cv} ||= $cv if check_file($cv);
    if ($cv->can("PADLIST")        &&
        $cv->PADLIST->can("ARRAY") &&
        $cv->PADLIST->ARRAY        &&
        $cv->PADLIST->ARRAY->can("ARRAY")) {
        $Cvs{$_} ||= $_
          for grep ref eq "B::CV" && check_file($_), $cv->PADLIST->ARRAY->ARRAY;
    }
};

sub sub_info {
    my ($cv) = @_;
    my ($name, $start) = ("--unknown--", 0);
    my $gv = $cv->GV;
    if ($gv && !$gv->isa("B::SPECIAL")) {
        return unless $gv->can("SAFENAME");
        $name = $gv->SAFENAME;
        # print STDERR "--[$name]--\n";
        $name =~ s/(__ANON__)\[.+:\d+\]/$1/ if defined $name;
    }
    my $root = $cv->ROOT;
    if ($root->can("first")) {
        my $lineseq = $root->first;
        if ($lineseq->can("first")) {
            # normal case
            $start = $lineseq->first;
        } elsif ($lineseq->name eq "nextstate") {
            # completely empty sub - sub empty { }
            $start = $lineseq;
        }
    }
    ($name, $start)
}

sub add_cvs {
    $Cvs{$_} ||= $_ for grep check_file($_), B::main_cv->PADLIST->ARRAY->ARRAY;
}

sub check_files {
    # print STDERR "Checking files\n";

    add_cvs();

    my %seen_pkg;
    my %seen_cv;

    walksymtable(\%main::, "find_cv", sub { !$seen_pkg{$_[0]}++ });

    my $l = sub {
        my ($cv) = @_;
        my $line = 0;
        my ($name, $start) = sub_info($cv);
        if ($start) {
            local ($Line, $File);
            get_location($start);
            $line = $Line;
            # print STDERR "$name - $File:$Line\n";
        }
        ($line, $name)
    };

    # print Dumper \%Cvs;

    @Cvs = map  $_->[0],
           sort { $a->[1] <=> $b->[1] || $a->[2] cmp $b->[2] }
           map  [ $_, $l->($_) ],
           grep !$seen_cv{$$_}++,
           values %Cvs;

    # Hack to bump up the refcount of the subs.  If we don't do this then the
    # subs in some modules don't seem to be around when we get to looking at
    # them.  I'm not sure why this is, and it seems to me that this hack could
    # affect the order of destruction, but I've not seen any problems.  Yet.
    # object_2svref doesn't exist before 5.8.1.
    @Subs = map $_->object_2svref, @Cvs if $] >= 5.008001;
}

my %Seen;

sub report {
    local $@;
    eval { _report() };
    if ($@) {
        print STDERR <<"EOM" unless $Silent;
Devel::Cover: Oops, it looks like something went wrong writing the coverage.
              It's possible that more bad things may happen but we'll try to
              carry on anyway as if nothing happened.  At a minimum you'll
              probably find that you are missing coverage.  If you're
              interested, the problem was:

$@

EOM
    }
    return unless $Self_cover;
    $Self_cover_run = 1;
    _report();
}

sub _report {
    local @SIG{qw(__DIE__ __WARN__)};
    # $SIG{__DIE__} = \&Carp::confess;

    $Run{finish} = get_elapsed() / 1e6;

    die "Devel::Cover::import() not run: " .
        "did you require instead of use Devel::Cover?\n"
        unless defined $Dir;

    my @collected = get_coverage();
    return unless @collected;
    set_coverage("none") unless $Self_cover;

    my $starting_dir = $1 if Cwd::getcwd() =~ /(.*)/;
    chdir $Dir or die __PACKAGE__ . ": Can't chdir $Dir: $!\n";

    $Run{collected} = \@collected;
    $Structure      = Devel::Cover::DB::Structure->new(
        base        => $DB,
        loose_perms => $Loose_perms,
    );
    $Structure->read_all;
    $Structure->add_criteria(@collected);
    # print STDERR "Start structure: ", Dumper $Structure;

    # print STDERR "Processing cover data\n@Inc\n";
    $Coverage = coverage(1) || die "No coverage data available.\n";
    # print STDERR Dumper $Coverage;

    check_files();

    unless ($Subs_only) {
        get_cover(main_cv, main_root);
        get_cover($_)
            for B::begin_av()->isa("B::AV") ? B::begin_av()->ARRAY : ();
        if (exists &B::check_av) {
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
    for my $file (sort keys %files) {
        # print STDERR "looking at $file\n";
        unless (use_file($file)) {
            # print STDERR "deleting $file\n";
            delete $Run{count}->{$file};
            delete $Run{vec}  ->{$file};
            $Structure->delete_file($file);
            next;
        }

        # $Structure->add_digest($file, \%Run);

        for my $run (keys %{$Run{vec}{$file}}) {
            delete $Run{vec}{$file}{$run} unless $Run{vec}{$file}{$run}{size};
        }

        $Structure->store_counts($file);
    }

    # print STDERR "End structure: ", Dumper $Structure;

    my $run = time . ".$$." . sprintf "%05d", rand 2 ** 16;
    my $cover = Devel::Cover::DB->new(
        base        => $DB,
        runs        => { $run => \%Run },
        structure   => $Structure,
        loose_perms => $Loose_perms,
    );

    my $dbrun = "$DB/runs";
    unless (mkdir $dbrun) {
        die "Can't mkdir $dbrun $!" unless -d $dbrun;
    }
    chmod 0777, $dbrun if $Loose_perms;
    $dbrun .= "/$run";

    print OUT __PACKAGE__, ": Writing coverage database to $dbrun\n"
        unless $Silent;
    $cover->write($dbrun);
    $Digests->write;
    $cover->print_summary if $Summary && !$Silent;

    if ($Self_cover && !$Self_cover_run) {
        $cover->delete;
        delete $Run{vec};
    }
    chdir $starting_dir;
}

sub add_subroutine_cover {
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

sub add_statement_cover {
    my ($op) = @_;

    get_location($op);
    return unless $File;

    # print STDERR "Stmt $File:$Line: $op $$op ", $op->name, "\n";

    $Run{digests}{$File} ||= $Structure->set_file($File);
    my $key = get_key($op);
    my $val = $Coverage->{statement}{$key} || 0;
    my ($n, $new) = $Structure->add_count("statement");
    # print STDERR "Stmt $File:$Line - $n, $new\n";
    $Structure->add_statement($File, $Line) if $new;
    $Run{count}{$File}{statement}[$n] += $val;
    my $vec = $Run{vec}{$File}{statement};
    vec($vec->{vec}, $n, 1) = $val ? 1 : 0;
    $vec->{size} = $n + 1;
    no warnings "uninitialized";
    $Run{count}{$File}{time}[$n] += $Coverage->{time}{$key}
        if $Coverage{time} &&
           exists $Coverage->{time} && exists $Coverage->{time}{$key};
}

sub add_branch_cover {
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
        ($type eq "elsif" && !exists $Coverage->{branch}{$key})) {
        # and   => this could also be a plain if with no else or elsif
        # or    => this could also be an unless with no else or elsif
        # elsif => no subsequent elsifs or elses
        # True path taken if not short circuited.
        # False path taken if short circuited.
        $c = [ $c->[1] + $c->[2], $c->[3] ];
        # print STDERR "branch $type [@$c]\n";
    } else {
        $c = $Coverage->{branch}{$key} || [0, 0];
    }

    my ($n, $new) = $Structure->add_count("branch");
    $Structure->add_branch($file, [ $line, { text => $text } ]) if $new;
    my $ccount = $Run{count}{$file};
    if (exists $ccount->{branch}[$n]) {
        $ccount->{branch}[$n][$_] += $c->[$_] for 0 .. $#$c;
    } else {
        $ccount->{branch}[$n] = $c;
        my $vec = $Run{vec}{$File}{branch};
        vec($vec->{vec}, $vec->{size}++, 1) = $_ ||= 0 ? 1 : 0 for @$c;
    }

    # warn "branch $type %x [@$c] => [@{$ccount->{branch}[$n]}]\n", $$op;
}

sub add_condition_cover {
    my ($op, $strop, $left, $right) = @_;

    return unless $Collect && $Coverage{condition};

    my $key = get_key($op);
    # warn "Condition cover $$op from $File:$Line\n";
    # print STDERR "left:  [$left]\nright: [$right]\n";
    # use Carp "cluck"; cluck("from here");

    my $type = $op->name;
    $type =~ s/assign$//;
    $type = "or" if $type eq "dor";

    my $c = $Coverage->{condition}{$key};

    no warnings "uninitialized";

    my $count;

    if ($type eq "or" || $type eq "and") {
        my $r = $op->first->sibling;
        my $name = $r->name;
        $name = $r->first->name if $name eq "sassign";
        # TODO - exec?  any others?
        # print STDERR "Name [$name]", Dumper $c;
        if ($c->[5] || $name =~ $Const_right) {
            $c = [ $c->[3], $c->[1] + $c->[2] ];
            $count = 2;
            # print STDERR "Special short circuit\n";
        } else {
            @$c = @{$c}[$type eq "or" ? (3, 2, 1) : (3, 1, 2)];
            $count = 3;
        }
        # print STDERR "$type 3 $name [", join(",", @$c), "] $File:$Line\n";
    } elsif ($type eq "xor") {
        # !l&&!r  l&&!r  l&&r  !l&&r
        @$c = @{$c}[3, 2, 4, 1];
        $count = 4;
    } else {
        die qq(Unknown type "$type" for conditional);
    }

    my $structure = {
        type  => "${type}_${count}",
        op    => $strop,
        left  => $left,
        right => $right,
    };

    my ($n, $new) = $Structure->add_count("condition");
    $Structure->add_condition($File, [ $Line, $structure ]) if $new;
    my $ccount = $Run{count}{$File};
    if (exists $ccount->{condition}[$n]) {
        $ccount->{condition}[$n][$_] += $c->[$_] for 0 .. $#$c;
    } else {
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
BEGIN {
    $Original{deparse}     = \&B::Deparse::deparse;
    $Original{logop}       = \&B::Deparse::logop;
    $Original{logassignop} = \&B::Deparse::logassignop;
}

sub deparse {
    my $self = shift;
    my ($op, $cx) = @_;

    my $deparse;

    if ($Collect) {
        my $class = class($op);
        my $null  = $class eq "NULL";

        my $name = $op->can("name") ? $op->name : "Unknown";

        # print STDERR "$class:$name ($$op) at $File:$Line\n";
        # print STDERR "[$Seen{statement}{$$op}] [$Seen{other}{$$op}]\n";
        # use Carp "cluck"; cluck("from here");

        return "" if $name eq "padrange";

        unless ($Seen{statement}{$$op} || $Seen{other}{$$op}) {
            # Collect everything under here.
            local ($File, $Line) = ($File, $Line);
            # print STDERR "Collecting $$op under $File:$Line\n";
            $deparse = eval { local $^W; $Original{deparse}->($self, @_) };
            $deparse =~ s/^\010+//mg if defined $deparse;
            $deparse = "Deparse error: $@" if $@;
            # print STDERR "Collected $$op under $File:$Line\n";
            # print STDERR "Collect Deparse $op $$op => <$deparse>\n";
        }

        # Get the coverage on this op.

        if ($class eq "COP" && $Coverage{statement}) {
            # print STDERR "COP $$op, seen [$Seen{statement}{$$op}]\n";
            my $nnnext = "";
            eval {
                my $next   = $op->next;
                my $nnext  = $next && $next->next;
                   $nnnext = $nnext && $nnext->next;
            };
            # print STDERR "COP $$op, ", $next, " -> ", $nnext,
                                              # " -> ", $nnnext, "\n";
            if ($nnnext) {
                add_statement_cover($op) unless $Seen{statement}{$$op}++;
            }
        } elsif (!$null && $name eq "null"
                      && ppname($op->targ) eq "pp_nextstate"
                      && $Coverage{statement}) {
            # If the current op is null, but it was nextstate, we can still
            # get at the file and line number, but we need to get dirty.

            bless $op, "B::COP";
            # print STDERR "null $$op, seen [$Seen{statement}{$$op}]\n";
            add_statement_cover($op) unless $Seen{statement}{$$op}++;
            bless $op, "B::$class";
        } elsif ($Seen{other}{$$op}++) {
            # print STDERR "seen [$Seen{other}{$$op}]\n";
            return ""  # Only report on each op once.
        } elsif ($name eq "cond_expr") {
            local ($File, $Line) = ($File, $Line);
            my $cond  = $op->first;
            my $true  = $cond->sibling;
            my $false = $true->sibling;
            if (!($cx < 1 && (is_scope($true) && $true->name ne "null") &&
                    (is_scope($false) || is_ifelse_cont($false))
                    && $self->{'expand'} < 7)) {
                { local $Collect; $cond = $self->deparse($cond, 8) }
                add_branch_cover($op, "if", "$cond ? :", $File, $Line);
            } else {
                { local $Collect; $cond = $self->deparse($cond, 1) }
                add_branch_cover($op, "if", "if ($cond) { }", $File, $Line);
                while (class($false) ne "NULL" && is_ifelse_cont($false)) {
                    my $newop   = $false->first;
                    my $newcond = $newop->first;
                    my $newtrue = $newcond->sibling;
                    if ($newcond->name eq "lineseq") {
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
    } else {
        local ($File, $Line) = ($File, $Line);
        # print STDERR "Starting plain deparse at $File:$Line\n";
        $deparse = eval { local $^W; $Original{deparse}->($self, @_) };
        $deparse = "" unless defined $deparse;
        $deparse =~ s/^\010+//mg;
        $deparse = "Deparse error: $@" if $@;
        # print STDERR "Ending plain deparse at $File:$Line\n";
        # print STDERR "Deparse => <$deparse>\n";
    }

    # print STDERR "Returning [$deparse]\n";
    $deparse
}

sub logop {
    my $self = shift;
    my ($op, $cx, $lowop, $lowprec, $highop, $highprec, $blockname) = @_;
    my $left  = $op->first;
    my $right = $op->first->sibling;
    # print STDERR "left [$left], right [$right]\n";
    my ($file, $line) = ($File, $Line);

    if ($cx < 1 && is_scope($right) && $blockname && $self->{expand} < 7) {
        # print STDERR 'if ($a) {$b}', "\n";
        # if ($a) {$b}
        $left  = $self->deparse($left,  1);
        $right = $self->deparse($right, 0);
        add_branch_cover($op, $lowop, "$blockname ($left)", $file, $line)
            unless $Seen{branch}{$$op}++;
        return "$blockname ($left) {\n\t$right\n\b}\cK"
    } elsif ($cx < 1 && $blockname && !$self->{parens} && $self->{expand} < 7) {
        # print STDERR '$b if $a', "\n";
        # $b if $a
        $right = $self->deparse($right, 1);
        $left  = $self->deparse($left,  1);
        add_branch_cover($op, $lowop, "$blockname $left", $file, $line)
            unless $Seen{branch}{$$op}++;
        return "$right $blockname $left"
    } elsif ($cx > $lowprec && $highop) {
        # print STDERR '$a && $b', "\n";
        # $a && $b
        {
            local $Collect;
            $left  = $self->deparse_binop_left ($op, $left,  $highprec);
            $right = $self->deparse_binop_right($op, $right, $highprec);
        }
        # print STDERR "left [$left], right [$right]\n";
        add_condition_cover($op, $highop, $left, $right)
            unless $Seen{condition}{$$op}++;
        return $self->maybe_parens("$left $highop $right", $cx, $highprec)
    } else {
        # print STDERR '$a and $b', "\n";
        # $a and $b
        $left  = $self->deparse_binop_left ($op, $left,  $lowprec);
        $right = $self->deparse_binop_right($op, $right, $lowprec);
        add_condition_cover($op, $lowop, $left, $right)
            unless $Seen{condition}{$$op}++;
        return $self->maybe_parens("$left $lowop $right", $cx, $lowprec)
    }
}

sub logassignop {
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

sub get_cover {
    my $deparse = B::Deparse->new;

    my $cv = $deparse->{curcv} = shift;

    ($Sub_name, my $start) = sub_info($cv);

    # warn "get_cover: <$Sub_name>\n";
    return unless defined $Sub_name;  # Only happens within Safe.pm, AFAIK.
    # return unless length  $Sub_name;  # Only happens with Self_cover, AFAIK.

    get_location($start) if $start;
    # print STDERR "[[$File:$Line]]\n";
    # return unless length $File;
    return if length $File && !use_file($File);

    return if !$Self_cover_run && $File =~ /Devel\/Cover/;
    return if  $Self_cover_run && $File !~ /Devel\/Cover/;
    return if  $Self_cover_run &&
               $File =~ /Devel\/Cover\.pm$/ &&
               $Sub_name eq "import";

    # printf STDERR "getting cover for $Sub_name ($start), %x\n", $$cv;

    if ($start) {
        no warnings "uninitialized";
        if ($File eq $Structure->get_file && $Line == $Structure->get_line &&
            $Sub_name eq "__ANON__" && $Structure->get_sub_name eq "__ANON__") {
            # Merge instances of anonymous subs into one.
            # TODO - multiple anonymous subs on the same line.
        } else {
            my $count = $Sub_count->{$File}{$Line}{$Sub_name}++;
            $Structure->set_subroutine($Sub_name, $File, $Line, $count);
            add_subroutine_cover($start)
                if $Coverage{subroutine} || $Coverage{pod};  # pod requires subs
        }
    }

    if ($Pod && $Coverage{pod}) {
        my $gv = $cv->GV;
        if ($gv && !$gv->isa("B::SPECIAL")) {
            my $stash = $gv->STASH;
            my $pkg   = $stash->NAME;
            my $file  = $cv->FILE;
            my %opts;
            $Run{digests}{$File} ||= $Structure->set_file($File);
            if (ref $Coverage_options{pod}) {
                my $p;
                for (@{$Coverage_options{pod}}) {
                    if (/^package|(?:also_)?private|trust_me|pod_from|nocp$/) {
                        $opts{$p = $_} = [];
                    } elsif ($p) {
                        push @{$opts{$p}}, $_;
                    }
                }
                for $p (qw( private also_private trust_me )) {
                    next unless exists $opts{$p};
                    $_ = qr/$_/ for @{$opts{$p}};
                }
            }
            $Pod = "Pod::Coverage" if delete $opts{nocp};
            # print STDERR "$Pod, $File:$Line ($Sub_name) [$file($pkg)]",
            #              Dumper \%opts;
            if ($Pod{$pkg} ||= $Pod->new(package => $pkg, %opts)) {
                # print STDERR Dumper $Pod{$file};
                my $covered;
                for ($Pod{$pkg}->covered) {
                    $covered = 1, last if $_ eq $Sub_name;
                }
                unless ($covered) {
                    for ($Pod{$pkg}->uncovered) {
                        $covered = 0, last if $_ eq $Sub_name;
                    }
                }
                # print STDERR "covered ", $covered // "undef", "\n";
                if (defined $covered) {
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

"
We have normality, I repeat we have normality.
Anything you still can’t cope with is therefore your own problem.
"

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

To get coverage for an uninstalled module which uses L<Module::Build> (0.26 or
later):

 ./Build testcover

If the module does not use the t/*.t framework:

 PERL5OPT=-MDevel::Cover make test

If you want to get coverage for a program:

 perl -MDevel::Cover yourprog args
 cover

To alter default values:

 perl -MDevel::Cover=-db,cover_db,-coverage,statement,time yourprog args

=head1 DESCRIPTION

This module provides code coverage metrics for Perl.  Code coverage metrics
describe how thoroughly tests exercise code.  By using Devel::Cover you can
discover areas of code not exercised by your tests and determine which tests
to create to increase coverage.  Code coverage can be considered an indirect
measure of quality.

Although it is still being developed, Devel::Cover is now quite stable and
provides many of the features to be expected in a useful coverage tool.

Statement, branch, condition, subroutine, and pod coverage information is
reported.  Statement and subroutine coverage data should be accurate.  Branch
and condition coverage data should be mostly accurate too, although not always
what one might initially expect.  Pod coverage comes from L<Pod::Coverage>.
If L<Pod::Coverage::CountParents> is available it will be used instead.
Coverage data for other criteria are not yet collected.

The F<cover> program can be used to generate coverage reports.  Devel::Cover
ships with a number of different reports including various types of HTML
output, textual reports, a report to display missing coverage in the same
format as compilation errors and a report to display coverage information
within the Vim editor.

It is possible to add annotations to reports, for example you can add a column
to an HTML report showing who last changed a line, as determined by git blame.
Some annotation modules are shipped with Devel::Cover and you can easily
create your own.

The F<gcov2perl> program can be used to convert gcov files to C<Devel::Cover>
databases.  This allows you to display your C or XS code coverage together
with your Perl coverage, or to use any of the Devel::Cover reports to display
your C coverage data.

Code coverage data are collected by replacing perl ops with functions which
count how many times the ops are executed.  These data are then mapped back to
reality using the B compiler modules.  There is also a statement profiling
facility which should not be relied on.  For proper profiling use
L<Devel::NYTProf>.  Previous versions of Devel::Cover collected coverage data by
replacing perl's runops function.  It is still possible to switch to that mode
of operation, but this now gets little testing and will probably be removed
soon.  You probably don't care about any of this.

The most appropriate mailing list on which to discuss this module would be
perl-qa.  See L<http://lists.perl.org/list/perl-qa.html>.

The Devel::Cover repository can be found at
L<http://github.com/pjcj/Devel--Cover>.  This is also where problems should be
reported.

=head1 REQUIREMENTS AND RECOMMENDED MODULES

=head2 REQUIREMENTS

=over

=item * Perl 5.10.0 or greater.

Perl versions 5.6.1, 5.6.2 and 5.8.x may work to an extent but are unsupported.
Perl 5.8.7 has problems and may crash.

If you want to use an unsupported version you will need to set the environment
variable $DEVEL_COVER_UNSUPPORTED.  Unsupported versions are also untested.  I
will consider patches for unsupported versions only if they do not compromise
the code.  This is a vague, nebulous concept that I will decide on if and when
necessary.

If you are using an unsupported version, please let me know.  I don't want to
know if you are just testing Devel::Cover, only if you are seriously using it to
do code coverage analysis of real code.  If I get no reports of such usage then
I will remove support and delete the workarounds for versions of perl below
5.10.0.  I may do that anyway.

Different versions of perl may give slightly different results due to changes
in the op tree.

=item * The ability to compile XS extensions.

This means a working C compiler and make program at least.  If you built perl
from source you will have these already and they will be used automatically.
If your perl was built in some other way, for example you may have installed
it using your Operating System's packaging mechanism, you will need to ensure
that the appropriate tools are installed.

=item * L<Storable> and L<Digest::MD5>

Both are in the core in Perl 5.8.0 and above.

=back

=head2 OPTIONAL MODULES

=over

=item * L<Template>, and either L<PPI::HTML> or L<Perl::Tidy>

Needed if you want syntax highlighted HTML reports.

=item * L<Pod::Coverage> (0.06 or above) or L<Pod::Coverage::CountParents>

One is needed if you want Pod coverage.  If L<Pod::Coverage::CountParents> is
installed, it is preferred.

=item * L<Test::More>

Required if you want to run Devel::Cover's own tests.

=item * L<Test::Differences>

Needed if the tests fail and you would like nice output telling you why.

=item * L<Template> and L<Parallel::Iterator>

Needed if you want to run cpancover.

=item * L<JSON::MaybeXS>

JSON is used to store the coverage database if it is available. JSON::MaybeXS
will select the best JSON backend installed.

=back

=head2 Use with mod_perl

By adding C<use Devel::Cover;> to your mod_perl startup script, you should be
able to collect coverage information when running under mod_perl.  You can
also add any options you need at this point.  I would suggest adding this as
early as possible in your startup script in order to collect as much coverage
information as possible.

Alternatively, add -MDevel::Cover to the parameters for mod_perl.
In this example, Devel::Cover will be operating in silent mode.

 PerlSwitches -MDevel::Cover=-silent,1

=head1 OPTIONS

 -blib               - "use blib" and ignore files matching \bt/ (default true
                       if blib directory exists, false otherwise).
 -coverage criterion - Turn on coverage for the specified criterion.  Criteria
                       include statement, branch, condition, path, subroutine,
                       pod, time, all and none (default all available).
 -db cover_db        - Store results in coverage db (default ./cover_db).
 -dir path           - Directory in which coverage will be collected (default
                       cwd).
 -ignore RE          - Set REs of files to ignore (default "/Devel/Cover\b").
 +ignore RE          - Append to REs of files to ignore.
 -inc path           - Set prefixes of files to include (default @INC).
 +inc path           - Append to prefixes of files to include.
 -loose_perms val    - Use loose permissions on all files and directories in
                       the coverage db so that code changing EUID can still
                       write coverage information (default off).
 -merge val          - Merge databases, for multiple test benches (default on).
 -select RE          - Set REs of files to select (default none).
 +select RE          - Append to REs of files to select.
 -silent val         - Don't print informational messages (default off).
 -subs_only val      - Only cover code in subroutine bodies (default off).
 -replace_ops val    - Use op replacing rather than runops (default on).
 -summary val        - Print summary information if val is true (default on).

=head2 More on Coverage Options

You can specify options to some coverage criteria.  At the moment only pod
coverage takes any options.  These are the parameters which are passed into
the L<Pod::Coverage> constructor.  The extra options are separated by dashes,
and you may specify as many as you wish.  For example, to specify that all
subroutines containing xx are private, call Devel::Cover with the option
-coverage,pod-also_private-xx.

=head1 SELECTING FILES TO COVER

You may select the files for which you want to collect coverage data using the
select, ignore and inc options.  The system uses the following procedure to
decide whether a file will be included in coverage reports:

=over

=item * If the file matches a RE given as a select option, it will be
included.

=item * Otherwise, if it matches a RE given as an ignore option, it won't be
included.

=item * Otherwise, if it is in one of the inc directories, it won't be
included.

=item * Otherwise, it will be included.

=back

You may add to the REs to select by using +select, or you may reset the
selections using -select.  The same principle applies to the REs to ignore.

The inc directories are initially populated with the contents of perl's @INC
array.  You may reset these directories using -inc, or add to them using +inc.

Although these options take regular expressions, you should not enclose the RE
within // or any other quoting characters.

The options -coverage, [+-]select, [+-]ignore and [+-]inc can be specified
multiple times, but they can also take multiple comma separated arguments.  In
any case you should not add a space after the comma, unless you want the
argument to start with that literal space.

=head1 UNCOVERABLE CRITERIA

Sometimes you have code which is uncoverable for some reason.  Perhaps it is
an else clause that cannot be reached, or a check for an error condition that
should never happen.  You can tell Devel::Cover that certain criteria are
uncoverable and then they are not counted as errors when they are not
exercised.  In fact, they are counted as errors if they are exercised.

This feature should only be used as something of a last resort.  Ideally you
would find some way of exercising all your code.  But if you have analysed
your code and determined that you are not going to be able to exercise it, it
may be better to record that fact in some formal fashion and stop Devel::Cover
complaining about it, so that real problems are not lost in the noise.

If you have uncoverable criteria I suggest not using the default HTML report
(with uses html_minimal at the moment) because this sometimes shows uncoverable
points as uncovered.  Instead, you should use the html_basic report for HTML
output which should behave correctly in this regard.

There are two ways to specify a construct as uncoverable, one invasive and one
non-invasive.

=head2 Invasive specification

You can use special comments in your code to specify uncoverable criteria.
Comments are of the form:

 # uncoverable <criterion> [details]

The keyword "uncoverable" must be the first text in the comment.  It should be
followed by the name of the coverage criterion which is uncoverable.  There
may then be further information depending on the nature of the uncoverable
construct.

=head3 Statements

The "uncoverable" comment should appear on either the same line as the
statement, or on the line before it:

    $impossible++;  # uncoverable statement
    # uncoverable statement
    it_has_all_gone_horribly_wrong();

If there are multiple statements (or any other criterion) on a line you can
specify which statement is uncoverable by using the "count" attribute,
count:n, which indicates that the uncoverable statement is the nth statement
on the line.

    # uncoverable statement count:1
    # uncoverable statement count:2
    cannot_run_this(); or_this();

=head3 Branches

The "uncoverable" comment should specify whether the "true" or "false" branch
is uncoverable.

    # uncoverable branch true
    if (pi == 3)

Both branches may be uncoverable:

    # uncoverable branch true
    # uncoverable branch false
    if (impossible_thing_happened_one_way()) {
        handle_it_one_way();      # uncoverable statement
    } else {
        handle_it_another_way();  # uncoverable statement
    }

=head3 Conditions

Because of the way in which Perl short-circuits boolean operations, there are
three ways in which such conditionals can be uncoverable.  In the case of C<
$x && $y> for example, the left operator may never be true, the right operator
may never be true, and the whole operation may never be false.  These
conditions may be modelled thus:

    # uncoverable branch true
    # uncoverable condition left
    # uncoverable condition false
    if ($x && !$y) {
        $x++;  # uncoverable statement
    }

    # uncoverable branch true
    # uncoverable condition right
    # uncoverable condition false
    if (!$x && $y) {
    }

C<Or> conditionals are handled in a similar fashion (TODO - provide some
examples) but C<xor> conditionals are not properly handled yet.

=head3 Subroutines

A subroutine should be marked as uncoverable at the point where the first
statement is marked as uncoverable.  Ideally all other criteria in the
subroutine would be marked as uncoverable automatically, but that isn't the
case at the moment.

    sub z {
        # uncoverable subroutine
        $y++; # uncoverable statement
    }

=head2 Non-invasive specification

If you can't, or don't want to add coverage comments to your code, you can
specify the uncoverable information in a separate file.  By default the files
PWD/.uncoverable and HOME/.uncoverable are checked.  If you use the
-uncoverable_file parameter then the file you provide is checked as well as
those two files.

The interface to managing this file is the L<cover> program, and the options
are:

 -uncoverable_file
 -add_uncoverable_point
 -delete_uncoverable_point   **UNIMPLEMENTED**
 -clean_uncoverable_points   **UNIMPLEMENTED**

The parameter for -add_uncoverable_point is a string composed of up to seven
space separated elements: "$file $criterion $line $count $type $class $note".

The contents of the uncoverable file is the same, with one point per line.

=head1 ENVIRONMENT

=head2 User variables

The -silent option is turned on when Devel::Cover is invoked via
$HARNESS_PERL_SWITCHES or $PERL5OPT.  Devel::Cover tries to do the right thing
when $MOD_PERL is set.  $DEVEL_COVER_OPTIONS is appended to any options passed
into Devel::Cover.

=head2 Developer variables

When running Devel::Cover's own test suite, $DEVEL_COVER_DEBUG turns on
debugging information, $DEVEL_COVER_GOLDEN_VERSION overrides Devel::Cover's
own idea of which golden results it should test against, and
$DEVEL_COVER_NO_COVERAGE runs the tests without collecting coverage.
$DEVEL_COVER_DB_FORMAT may be set to "Sereal", "JSON" or "Storable" to
override the default choice of DB format (Sereal, then JSON if either are
available, otherwise Storable).  $DEVEL_COVER_IO_OPTIONS provides fine-grained
control over the DB format.  For example, setting it to "pretty" when the
format is JSON will store the DB in a readable JSON format.  $DEVEL_COVER_CPUS
overrides the automated detection of the number of CPUs to use in parallel
testing.

=head1 ACKNOWLEDGEMENTS

Some code and ideas cribbed from:

=over 4

=item * L<Devel::OpProf>

=item * L<B::Concise>

=item * L<B::Deparse>

=back

=head1 SEE ALSO

=over 4

=item * L<Devel::Cover::Tutorial>

=item * L<B>

=item * L<Pod::Coverage>

=back

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

=item * L<B>

=item * L<B::Debug>

=item * L<B::Deparse>

=item * L<Carp>

=item * L<Cwd>

=item * L<Digest::MD5>

=item * L<File::Path>

=item * L<File::Spec>

=item * L<Storable> or L<JSON::MaybeXS> (and its backend) or L<Sereal>

=back

=head2 Redefined subroutines

If you redefine a subroutine you may find that the original subroutine is not
reported on.  This is because I haven't yet found a way to locate the original
CV.  Hints, tips or patches to resolve this will be gladly accepted.

The module Test::TestCoverage uses this technique and so should not be used in
conjunction with Devel::Cover.

=head1 BUGS

Almost certainly.

See the BUGS file, the TODO file and the bug trackers at
L<https://github.com/pjcj/Devel--Cover/issues?sort=created&direction=desc&state=open>
and L<https://rt.cpan.org/Public/Dist/Display.html?Name=Devel-Cover>

Please report new bugs on Github.

=head1 LICENCE

Copyright 2001-2017, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available on CPAN and from my
homepage: http://www.pjcj.net/.

=cut

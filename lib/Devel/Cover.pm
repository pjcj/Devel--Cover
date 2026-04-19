# Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

our $VERSION;

BEGIN {
  # VERSION
}

use parent "DynaLoader";

use Devel::Cover::DB          ();
use Devel::Cover::DB::Digests ();
use Devel::Cover::Inc         ();

BEGIN { $VERSION //= $Devel::Cover::Inc::VERSION }

use B qw( main_cv main_root OPf_KIDS OPf_SPECIAL OPf_WANT ppname walksymtable );
use B::Deparse ();

# OPpSTATEMENT (added in 5.43.8) authoritatively distinguishes statement-form
# ops (if/unless/if-else) from expression-form (&&/and/?:)
BEGIN {
  my $v = $] >= 5.043008 ? 1 : 0;
  *Has_op_statement = sub () { $v };
  B->import("OPpSTATEMENT") if $v;
}

use Cwd         qw( abs_path getcwd );
use File::Spec  ();
use Time::HiRes ();

use Devel::Cover::Core qw( remove_contained_paths );

BEGIN {
  # Use Pod::Coverage if it is available
  eval "use Pod::Coverage 0.06";
  # If there is any error other than a failure to locate, report it
  die $@ if $@ && $@ !~ m/Can't locate Pod\/Coverage.+pm in \@INC/;

  # We'll prefer Pod::Coverage::CountParents
  eval "use Pod::Coverage::CountParents";
  die $@ if $@ && $@ !~ m/Can't locate Pod\/Coverage.+pm in \@INC/;
}

my $Initialised;  # import() has been called

my $Dir;                          # Directory in which coverage will be
                                  # collected
my $DB             = "cover_db";  # DB name
my $Merge          = 1;           # Merge databases
my $Summary        = 1;           # Output coverage summary
my $Subs_only      = 0;           # Coverage only for sub bodies
my $Self_cover_run = 0;           # Covering Devel::Cover now
my $Loose_perms    = 0;           # Use loose permissions in the cover DB

my @Ignore;                       # Packages to ignore
my @Inc;                          # Original @INC to ignore
my @Select;                       # Packages to select
my @Ignore_re;                    # Packages to ignore
my @Inc_re;                       # Original @INC to ignore
my @Select_re;                    # Packages to select

my $Pod
  = $INC{"Pod/Coverage/CountParents.pm"} ? "Pod::Coverage::CountParents"
  : $INC{"Pod/Coverage.pm"}              ? "Pod::Coverage"
  :                                        "";  # Type of pod coverage available
my %Pod;                                        # Pod coverage data

my @Cvs;        # All the Cvs we want to cover
my %Cvs;        # All the Cvs we want to cover
my @Subs;       # All the subs we want to cover
my $Sub_name;   # Name of the sub we are looking in
my $Sub_count;  # Count for multiple subs on same line

my $Coverage;   # Raw coverage data
my $Structure;  # Structure of the files
my $Digests;    # Digests of the files

my %Criteria;          # Names of coverage criteria
my %Coverage;          # Coverage criteria to collect
my %Coverage_options;  # Options for overage criteria

my %Run;               # Data collected from the run

my $Const_right = qr/^(?:const|s?refgen|gelem|die|undef|bless|anon(?:list|hash)|
                       emptyavhv|scalar|return|last|next|redo|goto|
                       exec|exit|warn)$/x;

# Check whether the right operand of a logical op is a constant-like expression
# whose truth value is fixed.  Unwraps sassign if present. Also handles
# multiconcat (Perl 5.28+) with truthy literal text - the constant string is
# element [1] of aux_list and does not depend on the CV passed.  We check
# truthiness rather than mere non-emptiness because "0" is the one non-empty
# string that is falsy in Perl.
sub _is_const_right ($op) {
  my $rhs  = $op->name eq "sassign" ? $op->first : $op;
  my $name = $rhs->name;
  return 1 if $name =~ $Const_right;
  return 0 unless ref($rhs) eq "B::UNOP_AUX" && $name eq "multiconcat";
  my @aux = $rhs->aux_list(main_cv);
  $aux[1]
}

# constant ops

our $File;                # Last filename we saw.  (localised)
our $Line;                # Last line number we saw.  (localised)
our $Collect;             # Whether or not we are collecting
                          # coverage data.  We make two passes
                          # over conditions.  (localised)
our %Files;               # Whether we are interested in files
                          # Used in runops function
our $Replace_ops;         # Whether we are replacing ops
our $Silent;              # Output nothing. Can be used anywhere
our $Ignore_covered_err;  # Don't flag an error when uncoverable
                          # code is covered.
our $Self_cover;          # Coverage of Devel::Cover

BEGIN {
  ($File, $Line, $Collect) = ("", 0, 1);
  $Silent = ($ENV{HARNESS_PERL_SWITCHES} || "") =~ /Devel::Cover/
    || ($ENV{PERL5OPT} || "") =~ /Devel::Cover/;
  *OUT = $ENV{DEVEL_COVER_DEBUG} ? *STDERR : *STDOUT;

  # Default to the value baked in by Makefile.PL; override below if we can get
  # the real @INC from a clean subprocess.
  @Inc = @Devel::Cover::Inc::Inc;
  if ($^X !~ /(?:apache2|httpd)$/ && !${^TAINT}) {
    eval {
      local %ENV = %ENV;
      # Clear *PERL* variables, but keep PERL5?LIB for local::lib environments
      /perl/i && !/^PERL5?LIB$/ && delete $ENV{$_} for keys %ENV;
      if (open my $fh, "-|", $^X, "-e", 'print join("\0", @INC)') {
        local $/ = "\0";
        chomp(my @inc = <$fh>);
        close $fh or die "Can't close pipe to $^X: $!";
        @Inc = @inc if @inc;
      }
    };
    if ($@) {
      print STDERR __PACKAGE__, ": Error getting \@INC: $@\n";
      @Inc = @Devel::Cover::Inc::Inc;
    }
  }

  @Inc     = map { -d () ? ($_ eq "." ? $_ : abs_path($_)) : () } @Inc;
  @Inc     = remove_contained_paths(getcwd, @Inc);
  @Ignore  = ("/Devel/Cover[./]") unless $Self_cover = $ENV{DEVEL_COVER_SELF};
  $^P     |= 0x004 | 0x100;  # save source lines; evals report file info
}

my $Use_deparse = $ENV{DEVEL_COVER_USE_DEPARSE};

sub version    { $VERSION }
sub has_select { scalar @Select_re }

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
      join(", ", @coverage), @coverage ? " and " : "", "$last.\n", $nopod,
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
    set_last_end() unless $run_end++
  }

  my $run_init = 0;

  sub first_init {
    collect_inits() unless $run_init++
  }
}

sub last_end {
  report() if $Initialised;
}

{
  no warnings "void";  # avoid "Too late to run ... block" warning
  INIT  { }  # dummy sub to make sure PL_initav is set up and populated
  END   { }  # dummy sub to make sure PL_endav  is set up and populated
  CHECK { set_first_init_and_end() }  # we really want to be first
}

sub CLONE ($class) {
  print STDERR <<EOM;

Unfortunately, Devel::Cover does not yet work with threads.  I have done
some work in this area, but there is still more to be done.

EOM
  require POSIX;
  POSIX::_exit(1);
}

$Replace_ops = !$Self_cover;

sub _parse_options ($o, $blib) {
  my %scalar_opt = (
    "-silent"      => \$Silent,
    "-dir"         => \$Dir,
    "-db"          => \$DB,
    "-loose_perms" => \$Loose_perms,
    "-merge"       => \$Merge,
    "-summary"     => \$Summary,
    "-blib"        => $blib,
    "-subs_only"   => \$Subs_only,
    "-replace_ops" => \$Replace_ops,
  );
  my %list_opt = ("ignore" => \@Ignore, "inc" => \@Inc, "select" => \@Select);

  @Inc    = () if "@$o" =~ /-inc /;
  @Ignore = () if "@$o" =~ /-ignore /;
  @Select = () if "@$o" =~ /-select /;
  while (@$o) {
    local $_ = shift @$o;
    if (my $ref = $scalar_opt{$_}) {
      $$ref = shift @$o;
    } elsif (/^-coverage/) {
      $Coverage{ +shift @$o } = 1 while @$o && $o->[0] !~ /^[-+]/;
    } elsif (/^[-+](\w+)/ && $list_opt{$1}) {
      push $list_opt{$1}->@*, shift @$o while @$o && $o->[0] !~ /^[-+]/;
    } else {
      warn __PACKAGE__ . ": Unknown option $_ ignored\n";
    }
  }
}

sub _init_db {
  if (defined $Dir) {
    $Dir = $1 if $Dir =~ /(.*)/;  # Die tainting
  } else {
    $Dir = $1 if Cwd::getcwd() =~ /(.*)/;
  }

  $DB = File::Spec->rel2abs($DB, $Dir);
  unless (mkdir $DB) {
    my $err = $!;
    die "Can't mkdir $DB as EUID $>: $err" unless -d $DB;
  }
  chmod 0777, $DB if $Loose_perms;
  ($DB) = abs_path($DB) =~ /(.*)/;
  Devel::Cover::DB->delete($DB) unless $Merge;
}

sub _init_coverage {
  %Files = ();  # start gathering file information from scratch

  for my $c (Devel::Cover::DB->new->criteria) {
    my $func = "coverage_$c";
    no strict "refs";
    $Criteria{$c} = $func->();
  }

  for (keys %Coverage) {
    my @c = split /-/;
    if (@c > 1) {
      $Coverage{ shift @c } = \@c;
      delete $Coverage{$_};
    }
    delete $Coverage{$_} unless length;
  }
  unless (keys %Coverage) {
    %Coverage = map { $_ => 1 } grep $_ ne "time", keys %Criteria;
  }
  %Coverage_options = %Coverage;
}

sub import ($class, @o) {
  return if $Initialised;

  # Die tainting
  # Anyone using this module can do worse things than messing with tainting
  my $options = ($ENV{DEVEL_COVER_OPTIONS} || "") =~ /(.*)/ ? $1 : "";
  @o = (@o, split /,/, $options);
  defined or $_ = "" for @o;

  my $blib = -d "blib";
  _parse_options(\@o, \$blib);

  if ($blib) {
    eval "use blib";
    for (@INC) { ($_) = /(.*)/ if ref $_ ne "CODE" }  # Die tainting
    push @Ignore, "^t/", '\\.t$', '^test\\.pl$';
  }

  my $ci = $^O eq "MSWin32";
  @Select_re = map qr/$_/, @Select;
  @Ignore_re = map qr/$_/, @Ignore;
  @Inc_re    = map $ci ? qr/^\Q$_\//i : qr/^\Q$_\//, @Inc;

  bootstrap Devel::Cover $VERSION;

  _init_db();
  _init_coverage();

  $Initialised = 1;

  if ($ENV{MOD_PERL}) {
    eval "BEGIN {}";
    check();
    set_first_init_and_end();
  }
}

sub populate_run {
  $Run{OS}      = $^O;
  $Run{perl}    = sprintf "%vd", $^V;
  $Run{dir}     = $Dir;
  $Run{run}     = $0;
  $Run{name}    = $Dir;
  $Run{version} = "unknown";

  my $mymeta = "$Dir/MYMETA.json";
  if (-e $mymeta) {
    eval {
      require CPAN::Meta;
      my $json = CPAN::Meta->load_file($mymeta)->as_struct;
      $Run{$_} = $json->{$_} for qw( name version abstract );
    }
  } elsif ($Dir =~ m|.*/([^/]+)$|) {
    my $filename = $1;
    eval {
      require CPAN::DistnameInfo;
      my $dinfo = CPAN::DistnameInfo->new($filename);
      $Run{name}    = $dinfo->dist;
      $Run{version} = $dinfo->version;
    }
  }

  $Run{start} = get_elapsed() / 1e6;
}

sub cover_names_to_val (@o) {
  my $val = 0;
  for my $c (@o) {
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

sub set_coverage    (@o) { set_criteria(cover_names_to_val(@o)) }
sub add_coverage    (@o) { add_criteria(cover_names_to_val(@o)) }
sub remove_coverage (@o) { remove_criteria(cover_names_to_val(@o)) }

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

  sub normalised_file ($file) {
    return $File_cache{$file} if exists $File_cache{$file};
    return $file              if $Normalising;
    $Normalising = 1;

    my $f = $file;
    $file =~ s/ \(autosplit into .*\)$//;
    $file =~ s/^\(eval in .*\) //;
    if (
         exists coverage(0)->{module}
      && exists coverage(0)->{module}{$file}
      && !File::Spec->file_name_is_absolute($file)
    ) {
      my $m = coverage(0)->{module}{$file};
      $file = File::Spec->rel2abs($file, $m->[1]);
    }

    my $inc;
    $inc ||= $file =~ $_ for @Inc_re;
    if ($inc && ($^O eq "MSWin32" || $^O eq "cygwin")) {
      # Windows' Cwd::_win32_cwd() calls eval which will recurse back
      # here if we call abs_path, so we just assume it's normalised.
      # warn "giving up on getting normalised filename from <$file>\n";
    } else {
      if (-e $file) {  # Windows likes the file to exist
        my $abs;
        $abs  = abs_path($file) unless -l $file;  # leave symbolic links
        $file = $abs if defined $abs;
      }
    }

    $file =~ s|\\|/|g       if $^O eq "MSWin32";
    $file =~ s|^\Q$Dir\E/|| if defined $Dir;

    $Digests ||= Devel::Cover::DB::Digests->new(db => $DB);
    $file      = $Digests->canonical_file($file);

    $Normalising = 0;
    $File_cache{$f} = $file
  }

}

sub get_location ($op) {
  return unless $op->can("file");  # How does this happen?
  $File = $op->file;
  $Line = $op->line;

  # If there's an eval, get the real filename.  Enabled from $^P & 0x100.
  while ($File =~ /^\(eval \d+\)\[(.*):(\d+)\]/) {
    ($File, $Line) = ($1, $2);
  }
  $File = normalised_file($File);

  if (!exists $Run{vec}{$File} && $Run{collected}) {
    my %vec;
    @vec{ $Run{collected}->@* } = ();
    delete $vec{time};
    $vec{subroutine}++ if exists $vec{pod};
    $Run{vec}{$File}{$_}->@{ "vec", "size" } = ("", 0) for keys %vec;
  }
}

sub use_file ($file) {
  state $find_filename = qr/
    (?:^\(eval\s \d+\)\[(.+):\d+\])      |
    (?:^\(eval\sin\s\w+\)\s(.+))         |
    (?:\(defined\sat\s(.+)\sline\s\d+\)) |
    (?:\[from\s(.+)\sline\s\d+\])
  /x;

  return 0 unless $file && $find_filename;  # global destruction, probably

  # If you call your file something that matches $find_filename then things
  # might go awry.  But it would be silly to do that, so don't.  This little
  # optimisation provides a reasonable speedup.
  return $Files{$file} if exists $Files{$file};

  # just don't call your filenames 0
  while ($file =~ $find_filename) { $file = $1 || $2 || $3 || $4 }
  $file =~ s/ \(autosplit into .*\)$//;

  return $Files{$file} if exists $Files{$file};
  return 0
    if $file =~ /\(eval \d+\)/
    || $file =~ /^\.\.[\/\\]\.\.[\/\\]lib[\/\\](?:Storable|POSIX).pm$/;

  my $f = normalised_file($file);

  for (@Select_re)          { return $Files{$file} = 1 if $f =~ $_ }
  for (@Ignore_re, @Inc_re) { return $Files{$file} = 0 if $f =~ $_ }

  $Files{$file} = -e $file ? 1 : 0;
  print STDERR __PACKAGE__ . qq(: Can't find file "$file": ignored.\n)
    unless $Files{$file}
    || $Silent
    || $file =~ $Devel::Cover::DB::Ignore_filenames;

  add_cvs();  # add CVs now in case of symbol table manipulation
  $Files{$file}
}

sub check_file ($cv) {
  return unless ref($cv) eq "B::CV";

  my $op = $cv->START;
  # Methods defined with the class feature start with a methstart op;
  # advance past it to reach the nextstate op that has file information.
  $op = $op->next if ref($op) eq "B::UNOP_AUX" && $op->name eq "methstart";
  return unless ref($op) eq "B::COP";

  my $file = $op->file;
  my $use  = use_file($file);

  $use
}

sub B::GV::find_cv ($gv) {
  my $cv = $gv->CV;
  return unless $$cv;

  $Cvs{$cv} ||= $cv if check_file($cv);
  if (
       $cv->can("PADLIST")
    && $cv->PADLIST->can("ARRAY")
    && $cv->PADLIST->ARRAY
    && $cv->PADLIST->ARRAY->can("ARRAY")
  ) {
    $Cvs{$_} ||= $_
      for grep ref eq "B::CV" && check_file($_), $cv->PADLIST->ARRAY->ARRAY;
  }
}

sub sub_info ($cv) {
  my ($name, $start) = ("--unknown--", 0);
  my $gv = $cv->GV;
  if ($gv && !$gv->isa("B::SPECIAL")) {
    return unless $gv->can("SAFENAME");
    $name = $gv->SAFENAME;
    $name =~ s/(__ANON__)\[.+:\d+\]/$1/ if defined $name;
  }
  my $root = $cv->ROOT;
  if ($root->can("first")) {
    my $lineseq = $root->first;
    if ($lineseq->can("first")) {
      # normal case
      $start = $lineseq->first;
      # methods defined with the class feature start with a methstart op
      $start = $start->sibling if $start->name eq "methstart";
      # signatures
      if ($start->name eq "null" && $start->can("first")) {
        my $lineseq2 = $start->first;
        if ($lineseq2->name eq "lineseq" && $lineseq2->can("first")) {
          my $cop = $lineseq2->first;
          $start = $cop if $cop->name eq "nextstate";
        }
      }
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
  add_cvs();

  my %seen_pkg;
  my %seen_cv;

  walksymtable(
    \%main::,
    "find_cv",
    sub ($pkg) {
      return 0 if $seen_pkg{$pkg}++;
      no strict "refs";
      $Cvs{$_} ||= $_
        for grep check_file($_), map B::svref_2object($_),
        adjust_blocks(\%{$pkg});
      1
    },
  );

  my $l = sub ($cv) {
    my $line = 0;
    my ($name, $start) = sub_info($cv);
    if ($start) {
      local ($Line, $File);
      get_location($start);
      $line = $Line;
    }
    $line = 0  unless defined $line;
    $name = "" unless defined $name;
    ($line, $name)
  };

  @Cvs = map $_->[0],
    sort { $a->[1] <=> $b->[1] || $a->[2] cmp $b->[2] } map [ $_, $l->($_) ],
    grep !$seen_cv{$$_}++, values %Cvs;

  # Hack to bump up the refcount of the subs.  If we don't do this then the
  # subs in some modules don't seem to be around when we get to looking at
  # them.  I'm not sure why this is, and it seems to me that this hack could
  # affect the order of destruction, but I've not seen any problems.  Yet.
  @Subs = map $_->object_2svref, @Cvs;
}

my %Seen;
my %Parent_map;

sub _op_parent ($op) { $Parent_map{$$op} }

# Walk down through wrapper ops (null, not, scope, etc.) to find
# the logop underneath that would have its own condition entry.
# Returns ($op, $negated) where $negated counts not ops traversed.
my %Is_condition_op = map { $_ => 1 } qw( and or dor xor );

sub _skip_to_condop ($op) {
  my $negated = 0;
  while ($op && $$op && !$Is_condition_op{ $op->name }) {
    last unless $op->flags & OPf_KIDS;
    $negated ^= 1 if $op->name eq "not";
    $op       = $op->first;
  }
  ($op, $negated)
}

# Resolve a child op to its condition address and negation flag.
sub _resolve_child_op ($child_op) {
  return unless $child_op;
  my ($op, $negated) = _skip_to_condop($child_op);
  ($op ? $$op : undef, $negated || undef)
}

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
  local @SIG{qw( __DIE__ __WARN__ )};

  $Run{finish} = get_elapsed() / 1e6;

  die "Devel::Cover::import() not run: "
    . "did you require instead of use Devel::Cover?\n"
    unless defined $Dir;

  my @collected = get_coverage();
  return               unless @collected;
  set_coverage("none") unless $Self_cover;

  my ($starting_dir) = Cwd::getcwd() =~ /(.*)/;
  chdir $Dir or die __PACKAGE__ . ": Can't chdir $Dir: $!\n";

  $Run{collected} = \@collected;
  require Devel::Cover::DB::Structure;
  $Structure = Devel::Cover::DB::Structure->new(base => $DB,
    loose_perms => $Loose_perms,);
  $Structure->read_all;
  $Structure->add_criteria(@collected);

  $Coverage = coverage(1) || die "No coverage data available.\n";

  check_files();

  unless ($Subs_only) {
    get_cover(main_cv, main_root);
    get_cover_progress(
      "BEGIN block", B::begin_av()->isa("B::AV") ? B::begin_av()->ARRAY : ()
    );
    if (exists &B::check_av) {
      get_cover_progress(
        "CHECK block", B::check_av()->isa("B::AV") ? B::check_av()->ARRAY : ()
      );
    }
    # get_ends includes INIT blocks
    get_cover_progress(
      "END/INIT block",
      get_ends()->isa("B::AV") ? get_ends()->ARRAY : (),
    );
  }
  get_cover_progress("CV", @Cvs);

  _filter_cover_files();
  _write_coverage_db();

  chdir $starting_dir if $starting_dir;
}

sub _filter_cover_files {
  my %files;
  $files{$_}++ for keys $Run{count}->%*, keys $Run{vec}->%*;
  for my $file (sort keys %files) {
    unless (use_file($file)) {
      delete $Run{count}{$file};
      delete $Run{vec}{$file};
      $Structure->delete_file($file);
      next;
    }

    for my $run (keys $Run{vec}{$file}->%*) {
      delete $Run{vec}{$file}{$run} unless $Run{vec}{$file}{$run}{size};
    }

    $Structure->store_counts($file);
  }
}

sub _write_coverage_db {
  my $run = int(Time::HiRes::time() * 1e6) . ".$$." . sprintf "%05d",
    rand 2**16;
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
}

sub add_subroutine_cover ($op) {
  get_location($op);
  return unless $File;

  my $key = get_key($op);
  my $val = $Coverage->{statement}{$key} || 0;
  my ($n, $new) = $Structure->add_count("subroutine");
  $Structure->add_subroutine($File, [ $Line, $Sub_name ]) if $new;
  $Run{count}{$File}{subroutine}[$n] += $val;
  my $vec = $Run{vec}{$File}{subroutine};
  vec($vec->{vec}, $n, 1) = $val ? 1 : 0;
  $vec->{size} = $n + 1;
}

sub add_statement_cover ($op) {
  get_location($op);
  return unless $File;

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
    if $Coverage{time}
    && exists $Coverage->{time}
    && exists $Coverage->{time}{$key};
}

sub add_branch_cover ($op, $type, $text, $file, $line) {
  return unless $Collect && $Coverage{branch};

  $text =~ s/^\s+//;
  $text =~ s/\s+$//;

  my $key = get_key($op);
  my $c   = $Coverage->{condition}{$key};

  no warnings "uninitialized";

  if (
       $type eq "and"
    || $type eq "or"
    || ($type eq "elsif" && !exists $Coverage->{branch}{$key})
  ) {
    # and   => this could also be a plain if with no else or elsif
    # or    => this could also be an unless with no else or elsif
    # elsif => no subsequent elsifs or elses
    # True path taken if not short circuited.
    # False path taken if short circuited.
    $c = [ $c->[1] + $c->[2], $c->[3] ];
  } else {
    $c = $Coverage->{branch}{$key} || [ 0, 0 ];
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
}

sub add_condition_cover (
  $op, $strop, $left, $right,
  $left_op = undef,
  $right_op = undef,
) {
  return unless $Collect && $Coverage{condition};

  my $key  = get_key($op);
  my $type = $op->name;
  $type =~ s/assign$//;
  $type = "or" if $type eq "dor";

  my $c = $Coverage->{condition}{$key};

  no warnings "uninitialized";

  my $count;

  if ($type eq "or" || $type eq "and") {
    my $r = $op->first->sibling;
    if ($c->[5] || _is_const_right($r)) {
      $c     = [ $c->[3], $c->[1] + $c->[2] ];
      $count = 2;
    } else {
      @$c    = $c->@[ $type eq "or" ? (3, 2, 1) : (3, 1, 2) ];
      $count = 3;
    }
  } elsif ($type eq "xor") {
    # !l&&!r  l&&!r  l&&r  !l&&r
    @$c    = $c->@[ 3, 2, 4, 1 ];
    $count = 4;
  } else {
    die qq(Unknown type "$type" for conditional);
  }

  my ($la, $ln) = _resolve_child_op($left_op);
  my ($ra, $rn) = _resolve_child_op($right_op);

  my $structure = {
    type          => "${type}_${count}",
    op            => $strop,
    left          => $left,
    right         => $right,
    addr          => $$op,
    left_addr     => $la,
    right_addr    => $ra,
    left_negated  => $ln,
    right_negated => $rn,
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

{
  no warnings "once";
  *is_scope       = \&B::Deparse::is_scope;
  *is_state       = \&B::Deparse::is_state;
  *is_ifelse_cont = \&B::Deparse::is_ifelse_cont;
}

my %Original;
{

  BEGIN {
    $Original{deparse}      = \&B::Deparse::deparse;
    $Original{logop}        = \&B::Deparse::logop;
    $Original{logassignop}  = \&B::Deparse::logassignop;
    $Original{binop}        = \&B::Deparse::binop;
    $Original{const_dumper} = \&B::Deparse::const_dumper;
    $Original{const}        = \&B::Deparse::const if defined &B::Deparse::const;

    # B::Deparse has no pp_padrange - it handles padrange through lineseq
    # sequencing, never via direct dispatch.  When we call deparse() on
    # individual ops whose subtree contains a padrange, AUTOLOAD fires
    # with "unexpected OP_PADRANGE".  Return "" so the surrounding op
    # (aassign, entersub, etc.) still deparses correctly.
    *B::Deparse::pp_padrange = sub { "" }
      unless defined &B::Deparse::pp_padrange;
  }

  sub const_dumper (@o) {
    no warnings "redefine";

    local *B::Deparse::deparse      = $Original{deparse};
    local *B::Deparse::logop        = $Original{logop};
    local *B::Deparse::logassignop  = $Original{logassignop};
    local *B::Deparse::binop        = $Original{binop};
    local *B::Deparse::const_dumper = $Original{const_dumper};
    local *B::Deparse::const        = $Original{const} if $Original{const};

    $Original{const_dumper}->(@o);
  }

  sub const (@o) {
    no warnings "redefine";

    local *B::Deparse::deparse      = $Original{deparse};
    local *B::Deparse::logop        = $Original{logop};
    local *B::Deparse::logassignop  = $Original{logassignop};
    local *B::Deparse::binop        = $Original{binop};
    local *B::Deparse::const_dumper = $Original{const_dumper};

    $Original{const}->(@o);
  }

  sub _cover_statement_op ($op, $class, $null, $name) {
    if ($class eq "COP" && $Coverage{statement}) {
      my $nnnext = "";
      eval {
        my $next  = $op->next;
        my $nnext = $next && $next->next;
        $nnnext = $nnext && $nnext->next;
      };
      if ($nnnext && $name ne "null") {
        add_statement_cover($op) unless $Seen{statement}{$$op}++;
      }
      return 1;
    } elsif (
      !$null
      && $name eq "null"
      && ppname($op->targ) eq "pp_nextstate"
      && $Coverage{statement}
    ) {
      # If the current op is null, but it was nextstate, we can still
      # get at the file and line number, but we need to get dirty

      bless $op, "B::COP";
      add_statement_cover($op) unless $Seen{statement}{$$op}++;
      bless $op, "B::$class";
      return 1;
    }
    return 0;
  }

  sub _cover_cond_expr ($self, $op, $cx) {
    local ($File, $Line) = ($File, $Line);
    my $cond  = $op->first;
    my $true  = $cond->sibling;
    my $false = $true->sibling;

    # Since 5.43.2 empty if{} blocks may be optimised away, leaving only 2
    # children.  OPf_SPECIAL unset means the true block was removed; swap so
    # $false holds the else/elsif content. Gated on Has_op_statement because
    # the old heuristic cannot safely handle the swapped state.
    if (
         Has_op_statement
      && B::class($false) eq "NULL"
      && !($op->flags & OPf_SPECIAL)
    ) {
      ($true, $false) = ($false, $true);
    }

    # Use OPpSTATEMENT on 5.43.8+ to distinguish if/else from ?:
    my $is_statement;
    if (Has_op_statement) {
      $is_statement = $op->private & OPpSTATEMENT();
    } else {
      $is_statement
        = $cx < 1
        && $self->{expand} < 7
        && (
             B::class($false) eq "NULL"
          || $false->name eq "null"
          || ( (is_scope($true) && $true->name ne "null")
            && (is_scope($false) || is_ifelse_cont($false)))
        );
    }

    if (!$is_statement) {
      { local $Collect; $cond = $self->deparse($cond, 8) }
      add_branch_cover($op, "if", "$cond ? :", $File, $Line);
    } else {
      { local $Collect; $cond = $self->deparse($cond, 1) }
      add_branch_cover($op, "if", "if ($cond) { }", $File, $Line);
      while (B::class($false) ne "NULL" && is_ifelse_cont($false)) {
        my $newop   = $false->first;
        my $newcond = $newop->first;
        my $newtrue = $newcond->sibling;
        if ($newcond->name eq "lineseq") {
          # lineseq to ensure correct line numbers in elsif()
          # Bug #37302 fixed by change #33710
          $newcond = $newcond->first->sibling;
        }
        # last in chain is OP_AND => no else
        $false = $newtrue->sibling;
        { local $Collect; $newcond = $self->deparse($newcond, 1) }
        add_branch_cover($newop, "elsif", "elsif ($newcond) { }", $File, $Line);
      }
    }
  }

  sub deparse ($self, $op, $cx) {
    my $deparse;

    if ($Collect) {
      my $class = B::class($op);
      my $null  = $class eq "NULL";

      my $name = $op->can("name") ? $op->name : "Unknown";

      return "" if $name eq "padrange";

      unless ($Seen{statement}{$$op} || $Seen{other}{$$op}) {
        # Collect everything under here
        local ($File, $Line) = ($File, $Line);
        no warnings "redefine";
        my $use_dumper = $class eq "SVOP" && $name eq "const";
        local $self->{use_dumper} = 1 if $use_dumper;
        require Data::Dumper if $use_dumper;
        $deparse = eval { local $^W; $Original{deparse}->($self, $op, $cx) };
        $deparse =~ s/^\010+//mg       if defined $deparse;
        $deparse = "Deparse error: $@" if $@;
      }

      # Get the coverage on this op
      if (!_cover_statement_op($op, $class, $null, $name)) {
        return "" if $Seen{other}{$$op}++;  # Only report on each op once
        _cover_cond_expr($self, $op, $cx) if $name eq "cond_expr";
      }
    } else {
      local ($File, $Line) = ($File, $Line);
      $deparse = eval { local $^W; $Original{deparse}->($self, $op, $cx) };
      $deparse = "" unless defined $deparse;
      $deparse =~ s/^\010+//mg;
      $deparse = "Deparse error: $@" if $@;
    }

    $deparse
  }

  sub _classify_op ($self, $op, $cx, $blockname) {
    # $is_statement: controls deparse format (statement modifier vs
    # expression). On 5.43.8+ uses OPpSTATEMENT; on older Perls uses
    # B::Deparse's heuristic.
    my $is_statement
      = Has_op_statement() ? $op->private & OPpSTATEMENT() : $cx < 1
      && $blockname
      && $self->{expand} < 7;

    # $is_branch: controls coverage classification. Statement-level
    # expression logops (e.g. $y && $x++) are branches where the return
    # value is discarded, even though they aren't in statement form.
    my $is_branch = $is_statement || ($cx < 1 && $blockname);

    ($is_statement, $is_branch)
  }

  sub logop (
    $self, $op, $cx, $lowop, $lowprec,
    $highop    = undef,
    $highprec  = undef,
    $blockname = undef,
  ) {
    my $left  = $op->first;
    my $right = $op->first->sibling;
    my ($file, $line)        = ($File, $Line);
    my ($left_op, $right_op) = ($left, $right);

    $blockname &&= $self->keyword($blockname);

    my ($is_statement, $is_branch) = _classify_op($self, $op, $cx, $blockname);

    if ($is_statement && is_scope($right)) {
      # if ($a) {$b}
      $left  = $self->deparse($left,  1);
      $right = $self->deparse($right, 0);
      add_branch_cover($op, $lowop, "$blockname ($left)", $file, $line)
        unless $Seen{branch}{$$op}++;
      return "$blockname ($left) {\n\t$right\n\b}\cK"
    } elsif ($is_statement && (Has_op_statement || !$self->{parens})) {
      # $b if $a
      $right = $self->deparse($right, 1);
      $left  = $self->deparse($left,  1);
      add_branch_cover($op, $lowop, "$blockname $left", $file, $line)
        unless $Seen{branch}{$$op}++;
      return "$right $blockname $left"
    } elsif ($cx > $lowprec && $highop) {
      # $a && $b
      {
        local $Collect;
        $left  = $self->deparse_binop_left($op, $left, $highprec);
        $right = $self->deparse_binop_right($op, $right, $highprec);
      }
      add_condition_cover($op, $highop, $left, $right, $left_op, $right_op)
        unless $Seen{condition}{$$op}++;
      return $self->maybe_parens("$left $highop $right", $cx, $highprec)
    } else {
      # $a and $b
      $left  = $self->deparse_binop_left($op, $left, $lowprec);
      $right = $self->deparse_binop_right($op, $right, $lowprec);
      if ($is_branch) {
        add_branch_cover($op, $lowop, "$left $lowop $right", $file, $line)
          unless $Seen{branch}{$$op}++;
      } else {
        add_condition_cover($op, $lowop, $left, $right, $left_op, $right_op)
          unless $Seen{condition}{$$op}++;
      }
      return $self->maybe_parens("$left $lowop $right", $cx, $lowprec)
    }
  }

  sub logassignop ($self, $op, $cx, $opname) {
    my $left  = $op->first;
    my $right = $op->first->sibling->first;  # skip sassign
    my ($left_op, $right_op) = ($left, $right);
    $left  = $self->deparse($left,  7);
    $right = $self->deparse($right, 7);
    add_condition_cover($op, $opname, $left, $right, $left_op, $right_op);
    return $self->maybe_parens("$left $opname $right", $cx, 7);
  }

  sub binop ($self, $op, $cx, $opname, $prec, $flags = 0) {
    if (
         $] >= 5.041012
      && ($opname eq "xor" || $opname eq "^^")
      && !$Seen{condition}{$$op}++
    ) {
      my $left  = $op->first;
      my $right = $op->last;
      my ($left_op, $right_op) = ($left, $right);
      {
        local $Collect;
        $left  = $self->deparse_binop_left($op, $left, $prec);
        $right = $self->deparse_binop_right($op, $right, $prec);
      }
      add_condition_cover($op, $opname, $left, $right, $left_op, $right_op);
    }
    $Original{binop}->($self, $op, $cx, $opname, $prec, $flags)
  }

}

sub _parse_pod_options {
  my %opts;
  if (ref $Coverage_options{pod}) {
    my $p;
    for ($Coverage_options{pod}->@*) {
      if (/^package|(?:also_)?private|trustme|pod_from|nocp$/) {
        $opts{ $p = $_ } = [];
      } elsif ($p) {
        push $opts{$p}->@*, $_;
      }
    }
    for my $p (qw( private also_private trustme )) {
      next unless exists $opts{$p};
      $_ = qr/$_/ for $opts{$p}->@*;
    }
  }
  $Pod = "Pod::Coverage" if delete $opts{nocp};
  %opts
}

sub _add_pod_cover ($cv) {
  my $gv = $cv->GV;
  return if !$gv || $gv->isa("B::SPECIAL");

  my $pkg  = $gv->STASH->NAME;
  my %opts = _parse_pod_options();
  $Run{digests}{$File} ||= $Structure->set_file($File);
  $Pod{$pkg} ||= $Pod->new(package => $pkg, %opts);
  return unless $Pod{$pkg};

  my $covered;
  for ($Pod{$pkg}->covered) {
    $covered = 1, last if $_ eq $Sub_name;
  }
  unless ($covered) {
    for ($Pod{$pkg}->uncovered) {
      $covered = 0, last if $_ eq $Sub_name;
    }
  }
  return unless defined $covered;

  my ($n, $new) = $Structure->add_count("pod");
  $Structure->add_pod($File, [ $Line, $Sub_name ]) if $new;
  $Run{count}{$File}{pod}[$n] += $covered;
  my $vec = $Run{vec}{$File}{pod};
  vec($vec->{vec}, $n, 1) = $covered ? 1 : 0;
  $vec->{size} = $n + 1;
}

sub _want_cover_for {
  return unless defined $Sub_name;  # Only happens within Safe.pm, AFAIK
  return if length $File && !use_file($File);
  if (!$Self_cover_run && $File =~ /Devel\/Cover/) {
    # Allow partial self-coverage: if -select patterns are active and this DC
    # module matches one, let it through for instrumentation.
    return unless @Select_re && List::Util::any { $File =~ $_ } @Select_re;
  }
  return if $Self_cover_run && $File !~ /Devel\/Cover/;
  return
    if $Self_cover_run && $File =~ /Devel\/Cover\.pm$/ && $Sub_name eq "import";
  1
}

sub _add_subroutine_structure ($cv, $start) {
  return unless $start;
  no warnings "uninitialized";
  my $sub_id;
  if (
       $File eq $Structure->get_file
    && $Line == $Structure->get_line
    && $Sub_name eq "__ANON__"
    && $Structure->get_sub_name eq "__ANON__"
  ) {
    # Merge instances of anonymous subs into one
    # TODO - multiple anonymous subs on the same line
  } else {
    my $count = $Sub_count->{$File}{$Line}{$Sub_name}++;
    $sub_id = $Structure->set_subroutine($Sub_name, $File, $Line, $count);
    add_subroutine_cover($start)
      if $Coverage{subroutine} || $Coverage{pod};  # pod requires subs
  }
  _add_pod_cover($cv) if $Pod && $Coverage{pod};
  $sub_id
}

sub get_cover ($cv, $root = undef) {
  ($Sub_name, my $start) = sub_info($cv);

  get_location($start) if $start;
  return unless _want_cover_for();

  my $sub_id = _add_subroutine_structure($cv, $start);

  my ($cc, $end_line);
  if ($Use_deparse) {
    _get_cover_deparse($cv, $root);
  } else {
    ($cc, $end_line) = _get_cover_walk($cv, $root);
  }

  if ($sub_id && defined $cc) {
    $Structure->set_complexity($sub_id, $cc);
    $Structure->set_end_line($sub_id, $end_line) if defined $end_line;
  }
}

sub _get_cover_deparse ($cv, $root) {
  my $deparse = B::Deparse->new;
  $deparse->{curcv} = $cv;

  no warnings "redefine";

  local *B::Deparse::deparse      = \&deparse;
  local *B::Deparse::logop        = \&logop;
  local *B::Deparse::logassignop  = \&logassignop;
  local *B::Deparse::binop        = \&binop;
  local *B::Deparse::const_dumper = \&const_dumper;
  local *B::Deparse::const        = \&const if $Original{const};

  $root ? $deparse->deparse($root, 0) : $deparse->deparse_sub($cv, 0);
}

# --- XS op tree walker path ---

my $Shared_deparse;
my $Current_cop;

my $Has_pragmata = B::Deparse->can("pragmata");

sub _with_deparse ($cv, $use_dumper, $code) {
  $Shared_deparse ||= B::Deparse->new;
  $Shared_deparse->{curcv} = $cv;
  $Shared_deparse->pragmata($Current_cop) if $Has_pragmata && $Current_cop;
  require Data::Dumper                    if $use_dumper;
  local $Shared_deparse->{use_dumper} = $use_dumper;
  my $text = eval { local $^W; $code->() };
  defined $text ? $text =~ s/\x08//gr : ""  # strip B::Deparse unindent markers
}

sub _deparse_expr ($cv, $op, $cx, $use_dumper = 1) {
  _with_deparse($cv, $use_dumper, sub { $Shared_deparse->deparse($op, $cx) })
}

# Like _deparse_expr but uses B::Deparse's deparse_binop_left to avoid
# spurious parentheses when left-associative same-precedence ops nest
# (e.g. the inner && in "$a && $b && $c").
sub _deparse_binop_left ($cv, $op, $child, $prec, $use_dumper = 1) {
  _with_deparse(
    $cv,
    $use_dumper,
    sub {
      $Shared_deparse->deparse_binop_left($op, $child, $prec)
    },
  )
}

my %Logop_params = (
  and => [ "and", 3, "&&", 11, "if" ],
  or  => [ "or",  2, "||", 10, "unless" ],
  dor => [ "//",  10 ],
);

# Check if a null-statement op is inside a cond_expr/elsif condition
# lineseq (a dead COP from the compiler's scope creation).
sub _in_cond_expr_scope ($op) {
  my $p = _op_parent($op);
  return unless $p && $$p && $p->name eq "lineseq";
  my $gp = _op_parent($p);
  $gp && $$gp && ($gp->name eq "cond_expr" || $Seen{cond_expr}{$$gp})
}

# Check if a nextstate op is inside a signature argcheck block without
# a default-value sibling (i.e. plain param bookkeeping to skip).
sub _in_signature_argcheck ($op) {
  my $p = _op_parent($op);
  return unless $p && $$p && $p->name eq "lineseq";
  my $gp = _op_parent($p);
  return
       unless $gp
    && $$gp
    && $gp->name eq "null"
    && ppname($gp->targ) eq "pp_argcheck";
  # Inside argcheck - skip unless sibling is a default-value op.
  my $sib = $op->sibling;
  !(   $sib
    && $$sib
    && ($sib->flags & OPf_KIDS)
    && $sib->first->name =~ /^(?:argdefelem|paramtest)$/)
}

sub _walk_statement ($op, $type) {
  # Guard: skip statements with no real successors (trailing closing
  # braces, comment-only files, etc.)
  my $nnnext = "";
  eval {
    my $next  = $op->next;
    my $nnext = $next && $next->next;
    $nnnext = $nnext && $nnext->next;
  };
  return unless $nnnext;

  if ($type eq "null_statement") {
    my $class = B::class($op);
    return if $class eq "NULL";
    # Skip ex-nextstates inside cond_expr/elsif condition lineseqs -
    # these are dead COPs from the compiler's scope creation, not real
    # source statements.  Still update $File/$Line/$Current_cop so
    # that condition coverage for ops in this scope gets the right
    # line attribution.
    if (_in_cond_expr_scope($op)) {
      bless $op, "B::COP";
      get_location($op);
      $Current_cop = $op;
      # Leave blessed as B::COP - pragmata() needs COP methods.
      # The SV is mortal (from the XS callback) so this is safe.
      return;
    }
    bless $op, "B::COP";
    add_statement_cover($op) unless $Seen{statement}{$$op}++;
    bless $op, "B::$class";
  } else {
    # Skip nextstates inside signature argcheck blocks unless they
    # precede a default value.  Plain param assignments and argcheck
    # are bookkeeping; defaults are real conditional code.
    # Two optree layouts:
    #   5.38+:  nextstate → argelem(OPf_KIDS) → argdefelem
    #   5.43.4+: nextstate → null(OPf_KIDS) → paramtest
    return if _in_signature_argcheck($op);
    $Current_cop = $op;
    add_statement_cover($op) unless $Seen{statement}{$$op}++;
  }
}

sub _walk_cond_expr ($cv, $op) {
  return unless $Collect && $Coverage{branch};
  return if $Seen{cond_expr}{$$op};
  local ($File, $Line) = ($File, $Line);
  my $cond  = $op->first;
  my $true  = $cond->sibling;
  my $false = $true->sibling;

  if (
       Has_op_statement
    && B::class($false) eq "NULL"
    && !($op->flags & OPf_SPECIAL)
  ) {
    ($true, $false) = ($false, $true);
  }

  my $is_statement;
  if (Has_op_statement) {
    $is_statement = $op->private & OPpSTATEMENT();
  } else {
    $is_statement = (
           B::class($false) eq "NULL"
        || $false->name eq "null"
        || ( (is_scope($true) && $true->name ne "null")
          && (is_scope($false) || is_ifelse_cont($false)))
    );
  }

  if (!$is_statement) {
    my $text = _deparse_expr($cv, $cond, 8, 0);
    add_branch_cover($op, "if", "$text ? :", $File, $Line);
  } else {
    my $text = _deparse_expr($cv, $cond, 1, 0);
    add_branch_cover($op, "if", "if ($text) { }", $File, $Line);
    while (B::class($false) ne "NULL" && is_ifelse_cont($false)) {
      my $newop = $false->first;
      $Seen{cond_expr}{$$newop} = 1;
      my $newcond = $newop->first;
      my $newtrue = $newcond->sibling;
      if ($newcond->name eq "lineseq") {
        $newcond = $newcond->first->sibling;
      }
      $false = $newtrue->sibling;
      my $newtext = _deparse_expr($cv, $newcond, 1, 0);
      add_branch_cover($newop, "elsif", "elsif ($newtext) { }", $File, $Line);
    }
  }
}

# Determine cx for a logop by walking up the parent chain.
# B::Deparse determines cx from the deparsing call chain, not from
# OPf_WANT. The two diverge for return (want=NONE but cx=6 in deparse)
# and sort/map/grep blocks (want=SCALAR but cx=0 in deparse).
# The parent map (built by the XS walker) provides parent lookups on
# all Perl versions, not just 5.26+.
# Walk through null/ex-ops, stopping at block boundaries.
# Returns ($parent, $early_cx) - $early_cx is defined if a
# boundary was hit and the caller should return that value.
sub _skip_null_parents ($parent, $highprec, $lowprec) {
  while ($$parent && $parent->name eq "null") {
    if (my $targ = $parent->targ) {
      my $tname = ppname($targ);
      return ($parent, 0) if $tname =~ /^pp_(?:scope|leave)/;
      return ($parent, $highprec || $lowprec) if $tname eq "pp_return";
    }
    $parent = _op_parent($parent);
    last unless $parent && $$parent;
  }
  ($parent, undef)
}

# Determine cx for a logop whose parent is a lineseq.
# Returns 1 if the lineseq is inside a cond_expr/elsif wrapper, 0
# otherwise.
sub _lineseq_parent_cx ($parent) {
  my $gp = _op_parent($parent);
  return 0 unless $gp && $$gp;
  return 1 if $gp->name eq "cond_expr";
  return 1 if $Seen{cond_expr}{$$gp};
  0
}

# Determine cx for a logop by walking up the parent chain.
# B::Deparse determines cx from the deparsing call chain, not from
# OPf_WANT. The two diverge for return (want=NONE but cx=6 in deparse)
# and sort/map/grep blocks (want=SCALAR but cx=0 in deparse).
# The parent map (built by the XS walker) provides parent lookups on
# all Perl versions, not just 5.26+.
sub _logop_parent_cx ($op, $highprec, $lowprec) {
  my $parent = _op_parent($op);
  return 0 unless $parent && $$parent;
  # Skip null/ex-ops, but stop at block boundaries (ex-scope,
  # ex-leave*) since those indicate statement-level context.
  ($parent, my $early) = _skip_null_parents($parent, $highprec, $lowprec);
  return $early if defined $early;
  if ($parent && $$parent) {
    my $pname = $parent->name;
    return $highprec || $lowprec if $pname eq "return";
    return 1                     if $pname eq "cond_expr";
    # lineseq inside cond_expr/elsif-wrapper condition is cx=1.
    # The last elsif arm compiles to and/or instead of cond_expr;
    # those wrappers are tracked in %Seen{cond_expr}.
    return _lineseq_parent_cx($parent) if $pname eq "lineseq";
    return 0 if $pname =~ /^(?:scope|leave(?:sub|try|loop)?|sort)$/;
    # Nested logop (e.g. inner && in "$a && $b || $c") - B::Deparse
    # recurses into logop children at cx=1 (low-prec expression).
    return 1 if $pname =~ /^(?:and|or|dor)$/;
  }
  # Fallback for unrecognised parent structures (e.g. nested logops
  # where the optimizer has eliminated cond_expr): use OPf_WANT.
  # The parent map handles sort/return/leaveloop on all versions,
  # so this only fires for genuinely ambiguous cases.
  my $want = $op->flags & OPf_WANT;
  return 0 unless $want >= B::OPf_WANT_SCALAR;
  $highprec || $lowprec
}

# Check if a logop is a loop condition (and -> null* -> leaveloop).
sub _is_loop_condition ($op) {
  my $p = _op_parent($op);
  return unless $p && $$p;
  $p = _op_parent($p) while $p && $$p && $p->name eq "null";
  $p && $$p && $p->name eq "leaveloop"
}

# Resolve a blockname to its keyword form for statement-level logops,
# or clear it for expression-level.
sub _resolve_blockname ($blockname, $cx) {
  return undef if $cx >= 1;
  if ($blockname) {
    $Shared_deparse ||= B::Deparse->new;
    return $Shared_deparse->keyword($blockname);
  }
  $blockname
}

sub _walk_logop ($cv, $op) {
  return unless $Collect;
  return if $Seen{cond_expr}{$$op};
  my $name   = $op->name;
  my $params = $Logop_params{$name} || return;
  my ($lowop, $lowprec, $highop, $highprec, $blockname) = @$params;

  my $left  = $op->first;
  my $right = $op->first->sibling;
  my ($file, $line) = ($File, $Line);

  # Determine precedence context to match B::Deparse behaviour.
  # Always consult the parent chain when available - the XS walker's
  # in_logop nesting can cross block boundaries (e.g. sort block inside
  # a || expression), but B::Deparse resets cx at each block scope.
  my $cx = _logop_parent_cx($op, $highprec, $lowprec);
  $blockname = _resolve_blockname($blockname, $cx);

  # Loop conditions (and -> null* -> leaveloop) are always branches in
  # statement form, regardless of OPpSTATEMENT.
  $Shared_deparse ||= B::Deparse->new;
  my ($is_statement, $is_branch)
    = _is_loop_condition($op)
    ? (1, 1)
    : _classify_op($Shared_deparse, $op, $cx, $blockname);

  if ($is_statement) {
    my $l    = _deparse_expr($cv, $left, 1, 1);
    my $text = is_scope($right) ? "$blockname ($l)" : "$blockname $l";
    add_branch_cover($op, $lowop, $text, $file, $line)
      unless $Seen{branch}{$$op}++;
  } elsif ($cx > $lowprec && $highop) {
    my $l = _deparse_binop_left($cv, $op, $left, $highprec, 0);
    my $r = _deparse_expr($cv, $right, $highprec, 0);
    add_condition_cover($op, $highop, $l, $r, $left, $right)
      unless $Seen{condition}{$$op}++;
  } else {
    my $l = _deparse_binop_left($cv, $op, $left, $lowprec);
    my $r = _deparse_expr($cv, $right, $lowprec);
    if ($is_branch) {
      add_branch_cover($op, $lowop, "$l $lowop $r", $file, $line)
        unless $Seen{branch}{$$op}++;
    } else {
      add_condition_cover($op, $lowop, $l, $r, $left, $right)
        unless $Seen{condition}{$$op}++;
    }
  }
}

my %Logassign_opname
  = (andassign => "&&=", orassign => "||=", dorassign => "//=");

sub _walk_logassignop ($cv, $op) {
  return unless $Collect && $Coverage{condition};
  my $opname = $Logassign_opname{ $op->name } || return;
  my $left   = $op->first;
  my $right  = $op->first->sibling->first;               # skip sassign
  my $l      = _deparse_expr($cv, $left,  7);
  my $r      = _deparse_expr($cv, $right, 7);

  add_condition_cover($op, $opname, $l, $r, $left, $right);
}

sub _walk_xor ($cv, $op) {
  return unless $Collect && $Coverage{condition};
  return if $Seen{condition}{$$op}++;
  my $left   = $op->first;
  my $right  = $op->last;
  my $cx     = _logop_parent_cx($op, 10, 2);
  my $opname = ($] >= 5.040000 && $cx > 2) ? "^^" : "xor";
  my $l      = _deparse_expr($cv, $left,  $cx);
  my $r      = _deparse_expr($cv, $right, $cx);

  add_condition_cover($op, $opname, $l, $r, $left, $right);
}

sub _get_cover_walk ($cv, $root) {
  my $op = $root || $cv->ROOT;
  return unless $$op;
  my $decisions = 0;
  my $max_line  = $Line // 0;
  walk_ops(
    $op,
    sub ($op, $type, $cv_ref) {
      if ($type eq "statement" || $type eq "null_statement") {
        _walk_statement($op, $type);
        $max_line = $Line if defined $Line && $Line > $max_line;
      } elsif ($type eq "cond_expr") {
        $decisions++;
        _walk_cond_expr($cv_ref, $op);
      } elsif ($type eq "logop") {
        $decisions++;
        _walk_logop($cv_ref, $op);
      } elsif ($type eq "logassignop") {
        $decisions++;
        _walk_logassignop($cv_ref, $op);
      } elsif ($type eq "xor") {
        $decisions++;
        _walk_xor($cv_ref, $op);
      } elsif ($type eq "iter") {
        $decisions++;
      } elsif ($type eq "argdefelem") {
        $decisions++;
      }
    },
    $cv,
    \%Parent_map,
  );
  ($decisions + 1, $max_line)
}

sub _report_progress ($msg, $code, @items) {
  if ($Silent) {
    $code->($_) for @items;
    return;
  }
  my $tot  = @items || 1;
  my $prog = sub ($n) {
    print OUT "\r" . __PACKAGE__ . ": " . int(100 * $n / $tot) . "% ";
  };
  my ($old_pipe, $n, $start) = ($|, 0, time);
  $|++;
  print OUT __PACKAGE__, ": $msg\n";
  my $is_interactive = -t *OUT;
  for (@items) {
    $prog->($n++) if $is_interactive;
    $code->($_);
  }
  $prog->($n || 1);
  print OUT __PACKAGE__ . ": Done " if !$is_interactive;
  print OUT "- " . (time - $start) . "s taken\n";
  $| = $old_pipe;
}

sub get_cover_progress ($type, @cvs) {
  _report_progress("getting $type coverage", sub { get_cover($_) }, @cvs);
}

"
We have normality, I repeat we have normality.
Anything you still can’t cope with is therefore your own problem.
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover - Code coverage metrics for Perl

=head1 SYNOPSIS

To get coverage for an uninstalled module:

  cover -test

or

  cover -delete
  HARNESS_PERL_SWITCHES=-MDevel::Cover make test
  cover

or if you are using dzil (Dist::Zilla) and have installed
L<Dist::Zilla::App::Command::cover>:

  dzil cover

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

Devel::Cover is now quite stable and provides many of the features to be
expected in a useful coverage tool.

Statement, branch, condition, subroutine, and pod coverage information is
reported.  Statement and subroutine coverage data should be accurate.  Branch
and condition coverage data should be mostly accurate too, although not always
what one might initially expect.  Pod coverage comes from L<Pod::Coverage>. If
L<Pod::Coverage::CountParents> is available it will be used instead.

The F<cover> program can be used to generate coverage reports.  Devel::Cover
ships with a number of reports including various types of HTML output, textual
reports, a report to display missing coverage in the same format as compilation
errors and a report to display coverage information within the Vim editor.

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
perl-qa.  See L<https://lists.perl.org/list/perl-qa.html>.

The Devel::Cover repository can be found at
L<https://github.com/pjcj/Devel--Cover>.  This is also where problems should be
reported.

=head1 REQUIREMENTS AND RECOMMENDED MODULES

=head2 REQUIREMENTS

=over

=item * Perl 5.20.0 or greater.

The latest version of Devel::Cover on which Perl 5.12 to 5.18 was supported was
1.51.  The latest version of Devel::Cover on which Perl 5.10 was supported was
1.38.  The latest version of Devel::Cover on which Perl 5.8 was supported was
1.23.  Perl versions 5.6.1 and 5.6.2 were not supported after version 1.22.
Perl versions 5.6.0 and earlier were never supported.  Using Devel::Cover with
Perl 5.8.7 was always problematic and frequently led to crashes.

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
                        if blib directory exists, false otherwise)
  -coverage criterion - Turn on coverage for the specified criterion.  Criteria
                        include statement, branch, condition, path, subroutine,
                        pod, time, all and none (default all except time)
  -db cover_db        - Store results in coverage db (default ./cover_db)
  -dir path           - Directory in which coverage will be collected (default
                        cwd)
  -ignore RE          - Set regular expressions for files to ignore (default
                        "/Devel/Cover\b")
  +ignore RE          - Append to regular expressions of files to ignore
  -inc path           - Set prefixes of files to include (default @INC)
  +inc path           - Append to prefixes of files to include
  -loose_perms val    - Use loose permissions on all files and directories in
                        the coverage db so that code changing EUID can still
                        write coverage information (default off)
  -merge val          - Merge databases, for multiple test benches (default on)
  -select RE          - Set regular expressions of files to select (default
                        none)
  +select RE          - Append to regular expressions of files to select
  -silent val         - Don't print informational messages (default off)
  -subs_only val      - Only cover code in subroutine bodies (default off)
  -replace_ops val    - Use op replacing rather than runops (default on)
  -summary val        - Print summary information if val is true (default on)

=head2 More on Coverage Options

You can specify options to some coverage criteria.  At the moment only pod
coverage takes any options.  These are the parameters which are passed into
the L<Pod::Coverage> constructor.  The extra options are separated by dashes,
and you may specify as many as you wish.  For example, to specify that all
subroutines containing xx are private, call Devel::Cover with the option
-coverage,pod-also_private-xx.

Or, to ignore all files in C<t/lib> as well as files ending in C<Foo.pm>:

  cover -test -silent -ignore ^t/lib/,Foo.pm$

Note that C<-ignore> replaces any default ignore regexes.  To preserve any
ignore regexes which have already been set, use C<+ignore>:

  cover -test -silent +ignore ^t/lib/,Foo.pm$

=head1 SELECTING FILES TO COVER

You may select the files for which you want to collect coverage data using the
select, ignore and inc options.  The system uses the following procedure to
decide whether a file will be included in coverage reports:

=over

=item * If the file matches a RE given as a select option, it will be
included

=item * Otherwise, if it matches a RE given as an ignore option, it won't be
included

=item * Otherwise, if it is in one of the inc directories, it won't be
included

=item * Otherwise, it will be included

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

In all cases a L<class> attribute may be included in L<details>.  At present a
single class attribute is recognised: L<ignore_covered_err>.  Normally, an
error is flagged if code marked as L<uncoverable> is covered.  When the
L<ignore_covered_err> attribute is specified then such errors will not be
flagged.  This is a more precise method to flag such exceptions than the global
L<-ignore_covered_err> flag to the L<cover> program.

There is also a L<note> attribute which can also be included in L<details>.
This should be the final attribute and will consume all the remaining text.
Currently this attribute is not used, but it is intended as a form of
documentation for the uncoverable data.

Example:

  # uncoverable branch true count:1..3 class:ignore_covered_err note:error chk

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

If there is an elsif in the branch then it can be addressed as the second
branch on the line by using the "count" attribute.  Further elsifs are the
third and fourth "count" value, and so on:

  # uncoverable branch false count:2
  if ($thing == 1) {
    handle_thing_being_one();
  } elsif ($thing == 2) {
    handle_thing_being_tow();
  } else {
    die "thing can only be one or two, not $thing"; # uncoverable statement
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

As for branches, the "count" value may be used for either conditions in elsif
conditionals, or for complex conditions.

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

Note that when Devel::Cover is invoked via an environment variable, any modules
specified on the command line, such as via the -Mmodule option, will not be
covered.  This is because the environment variables are processed after the
command line and any code to be covered must appear after Devel::Cover has been
loaded.  To work around this, Devel::Cover can also be specified on the command
line.

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
L<https://github.com/pjcj/Devel--Cover/issues?state=open> and
L<https://rt.cpan.org/Public/Dist/Display.html?Name=Devel-Cover>

Please report new bugs on GitHub.

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available on CPAN and from my
homepage: https://pjcj.net/.

=cut

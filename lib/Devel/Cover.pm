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

# OPpSTATEMENT is imported conditionally below - perlimports must not re-add it
use B  ## no perlimports
  qw(
  main_cv
  main_root
  OPf_KIDS
  OPf_SPECIAL
  OPf_WANT
  SVf_ROK
  ppname
  walksymtable
  );
use B::Deparse ();

# OPpSTATEMENT (5.43.8+) distinguishes statement-form from expression-form ops
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
  eval "use Pod::Coverage 0.06";
  # If there is any error other than a failure to locate, report it
  die $@ if $@ && $@ !~ m/Can't locate Pod\/Coverage.+pm in \@INC/;

  # We'll prefer Pod::Coverage::CountParents
  eval "use Pod::Coverage::CountParents";
  die $@ if $@ && $@ !~ m/Can't locate Pod\/Coverage.+pm in \@INC/;
}

my $Initialised;  # import() has been called

my $Dir;                          # Directory in which coverage is collected
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

# The multiconcat string is aux_list element [1] and does not depend on the CV
sub _is_const_right ($op) {
  my $rhs  = $op->name eq "sassign" ? $op->first : $op;
  my $name = $rhs->name;
  return 1 if $name =~ $Const_right;
  return 0 unless ref($rhs) eq "B::UNOP_AUX" && $name eq "multiconcat";
  my @aux = $rhs->aux_list(main_cv);
  $aux[1]
}

our $File;                # Last filename we saw.  (localised)
our $Line;                # Last line number we saw.  (localised)
our $Walk_seen;           # CVs walked this check_files run.  (localised)
our $Collect;             # Whether we are collecting coverage data (localised)
our %Files;               # Cached use_file decisions, read by the XS side
our $Replace_ops;         # Whether we are replacing ops
our $Silent;              # Output nothing. Can be used anywhere
our $Ignore_covered_err;  # Don't flag an error when uncoverable code runs
our $Self_cover;          # Coverage of Devel::Cover

BEGIN {
  ($File, $Line, $Collect) = ("", 0, 1);
  $Silent = ($ENV{HARNESS_PERL_SWITCHES} || "") =~ /Devel::Cover/
    || ($ENV{PERL5OPT} || "") =~ /Devel::Cover/;
  *OUT = $ENV{DEVEL_COVER_DEBUG} ? *STDERR : *STDOUT;

  # Default to the @INC baked in by Makefile.PL, overridden below if possible
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

sub version    { $VERSION }
sub has_select { scalar @Select_re }

sub check {
  return unless $Initialised;

  check_files();

  set_coverage(keys %Coverage);
  my @coverage = get_coverage();
  %Coverage = map { $_ => 1 } @coverage;

  warn __PACKAGE__
    . ": mcdc coverage requires condition coverage; "
    . "no mcdc data will be collected.\n"
    if $Coverage{mcdc} && !$Coverage{condition} && !$Silent;

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

{
  no warnings "void";  # avoid "Too late to run CHECK block" warning
  CHECK { check }
}

sub first_end {
  state $run_end = 0;
  set_last_end() unless $run_end++
}

sub first_init {
  state $run_init = 0;
  collect_inits() unless $run_init++
}

sub last_end { report() if $Initialised }

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
  my %list_opt = (ignore => \@Ignore, inc => \@Inc, select => \@Select);

  my %reset;
  while (@$o) {
    local $_ = shift @$o;
    if (my $ref = $scalar_opt{$_}) {
      $$ref = shift @$o;
    } elsif (/^-coverage/) {
      $Coverage{ +shift @$o } = 1 while @$o && $o->[0] !~ /^[-+]/;
    } elsif (/^([-+])(\w+)/ && $list_opt{$2}) {
      $list_opt{$2}->@* = () if $1 eq "-" && !$reset{$2}++;
      push $list_opt{$2}->@*, shift @$o while @$o && $o->[0] !~ /^[-+]/;
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

  # Untaint - users of this module can do worse things than mess with tainting
  my $options = ($ENV{DEVEL_COVER_OPTIONS} || "") =~ /(.*)/ ? $1 : "";
  @o = (@o, split /,/, $options);
  defined or $_ = "" for @o;

  my $blib = -d "blib";
  _parse_options(\@o, \$blib);

  if ($blib) {
    eval "use blib";
    for (@INC) { ($_) = /(.*)/ if ref $_ ne "CODE" }  # Die tainting
    push @Ignore, "^t/", "^inc/", '\\.t$', '^test\\.pl$';
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
  return unless defined wantarray;  ## no critic (Wantarray)
  my @names;
  my $val = get_criteria();
  for my $c (sort keys %Criteria) {
    push @names, $c if $val & $Criteria{$c};
  }
  return wantarray ? @names : "@names";  ## no critic (Wantarray)
}

sub autosplit_parent ($file) {
  return $file unless $file =~ s/ \(autosplit into (.*)\)$//;
  my $al = $1;
  return $file if -e $file;
  my ($key) = $file =~ m{^blib/(?:lib|arch)/(.*)};
  return $file unless defined $key;
  my $pm = $INC{$key};
  return $file unless defined $pm && !ref $pm && $pm =~ /\Q$key\E$/;
  my $root = substr $pm, 0, length($pm) - length $key;
  $al =~ s{^blib/(?:lib|arch)/}{};
  -e "$root$al" ? $pm : $file
}

{

  my %File_cache;

  my $Normalising;

  sub normalised_file ($file) {
    return $File_cache{$file} if exists $File_cache{$file};
    return $file              if $Normalising;
    $Normalising = 1;

    my $f = $file;
    $file = autosplit_parent($file);
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
    $inc ||= $file =~ $_ for grep defined, @Inc_re;
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
  return if ${^GLOBAL_PHASE} eq "DESTRUCT";
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
  return 0 if ${^GLOBAL_PHASE} eq "DESTRUCT";

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
  $file = autosplit_parent($file);

  return $Files{$file} if exists $Files{$file};
  return 0             if $file =~ /\(eval \d+\)/;
  # AutoSplit index files are machine-generated, never real source
  return 0 if $file =~ /autosplit\.ix$/;

  my $f = normalised_file($file);

  for (grep defined, @Select_re) { return $Files{$file} = 1 if $f =~ $_ }
  for (grep defined, @Ignore_re, @Inc_re) {
    return $Files{$file} = 0 if $f =~ $_;
  }

  $Files{$file} = -e $file ? 1 : 0;
  print STDERR __PACKAGE__ . qq(: Can't find file "$file": ignored.\n)
    unless $Files{$file}
    || $Silent
    || $file =~ $Devel::Cover::DB::Ignore_filenames;

  add_cvs();
  $Files{$file}
}

# Sub-body prologue ops that carry no file information
my %Prologue_op = map { $_ => 1 } qw( methstart introcv clonecv );

sub check_file ($cv) {
  return unless ref($cv) eq "B::CV";

  my $op = $cv->START;
  $op = $op->next
    while ref($op) && $op->can("name") && $Prologue_op{ $op->name };
  return unless ref($op) eq "B::COP";

  my $file = $op->file;
  my $use  = use_file($file);

  $use
}

sub recoverable_sub ($cv) {
  my $gv = $cv->GV;
  return 0 unless ref $gv && !$gv->isa("B::SPECIAL");
  my $name = $gv->NAME;
  defined $name
    && $name =~ /^\w+$/
    && $name ne "__ANON__"
    && $name !~ /^(?:BEGIN|END|INIT|CHECK|UNITCHECK)$/
}

sub ref_cvs ($sv, $seen, $depth = 1) {
  my $r = ref $sv or return ();
  if ($r ne "B::AV" && $r ne "B::HV") {
    return ()
      unless $sv->can("FLAGS") && $sv->can("RV") && ($sv->FLAGS & SVf_ROK);
    $sv = $sv->RV;
    $r  = ref $sv;
    return recoverable_sub($sv) ? $sv : () if $r eq "B::CV";
    return () unless $r eq "B::AV" || $r eq "B::HV";
  }
  return () unless $depth;
  return () if $sv->can("SvSTASH") && ref($sv->SvSTASH) ne "B::SPECIAL";
  return () if $sv->MAGICAL;
  return () if $seen->{$$sv}++;
  my @elems = $r eq "B::AV" ? $sv->ARRAY : do { my %h = $sv->ARRAY; values %h };
  map ref_cvs($_, $seen, $depth - 1), @elems
}

sub pad_cvs ($cv, $seen = {}) {
  $seen->{$$cv}++;
  my $padlist = $cv->can("PADLIST") ? $cv->PADLIST : undef;
  my $array   = $padlist && $padlist->can("ARRAY") ? $padlist->ARRAY : undef;
  return unless $array && $array->can("ARRAY");
  my @cvs = grep ref eq "B::CV" && check_file($_) && !$seen->{$$_}++,
    map ref eq "B::CV" ? $_ : ref_cvs($_, $seen), $array->ARRAY;
  my $names = $padlist->ARRAYelt(0);
  push @cvs, grep ref eq "B::CV" && check_file($_) && !$seen->{$$_}++,
    map ref && $_->can("PROTOCV") ? $_->PROTOCV : (), $names->ARRAY
    if $names && $names->can("ARRAY");
  (@cvs, map pad_cvs($_, $seen), @cvs)
}

sub B::GV::find_cv ($gv) {
  my $cv = $gv->CV;
  return unless $$cv;

  my $seen = $Walk_seen // {};
  return if $seen->{$$cv};

  $Cvs{$cv} ||= $cv if check_file($cv);
  $Cvs{$_}  ||= $_ for pad_cvs($cv, $seen);
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
      # step past a my sub prologue wrapped in a nested lineseq
      if (
           $start->name eq "lineseq"
        && $start->can("first")
        && $start->first->can("name")
        && $Prologue_op{ $start->first->name }
      ) {
        my $sibling = $start->sibling;
        $start = $sibling if ref $sibling && $sibling->can("name");
      }
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

sub add_cvs ($seen = {}) {
  $Cvs{$_} ||= $_ for pad_cvs(B::main_cv, $seen);
}

sub check_files {
  local $Walk_seen = {};
  add_cvs($Walk_seen);

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
    ($line, $name, $start ? $$start : 0)
  };

  my %seen_start;
  @Cvs = map $_->[0],
    sort { $a->[1] <=> $b->[1] || $a->[2] cmp $b->[2] }
    grep { !$_->[3] || !$seen_start{ $_->[3] }++ } map [$_, $l->($_)],
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

my %Is_condition_op = map { $_ => 1 } qw( and or dor xor );

sub _skip_to_condop ($op) {
  my $negated = 0;
  while ($op && $$op && !$Is_condition_op{ $op->name }) {
    last unless $op->flags & OPf_KIDS;
    # OP_CUSTOM is a value-producing operator, not a wrapper.  B blesses
    # unregistered custom ops as plain B::OP regardless of their real
    # structure, so calling ->first would die.  Stop here.
    last if $op->name eq "custom";
    $negated ^= 1 if $op->name eq "not";
    $op = $op->first;
  }
  ($op, $negated)
}

sub _resolve_child_op ($child_op) {
  return unless $child_op;
  my ($op, $negated) = _skip_to_condop($child_op);
  ($op ? $$op : undef, $negated || undef)
}

sub special_block_cvs {
  my @avs = B::begin_av();
  push @avs, B::check_av() if exists &B::check_av;
  push @avs, get_ends();
  map $_->isa("B::AV") ? $_->ARRAY : (), @avs
}

sub _seed_pad_cvs (@require_trees) {
  $Cvs{$_} ||= $_ for map pad_cvs($_->[0]), @require_trees;
  return if $Subs_only;
  $Cvs{$_} ||= $_ for map pad_cvs($_), special_block_cvs();
}

sub _seed_entered_subs () {
  $Cvs{$_} ||= $_
    for grep recoverable_sub($_) && check_file($_), get_entered_subs();
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
  if ($Self_cover) {
    $Self_cover_run = 1;
    _report();
  }
  release_require_trees();
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
    loose_perms => $Loose_perms);
  $Structure->read_all;
  $Structure->add_criteria(@collected);

  $Coverage = coverage(1) || die "No coverage data available.\n";

  my @require_trees = get_require_trees();
  my %latest_tree;
  $latest_tree{ $_->[2] } = $_ for @require_trees;
  @require_trees          = grep $latest_tree{ $_->[2] } == $_, @require_trees;

  _seed_pad_cvs(@require_trees);
  _seed_entered_subs();

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
  unless ($Subs_only) {
    _report_progress(
      "getting require file coverage",
      sub ($tree) {
        my ($cv, $root, $file) = @$tree;
        local ($File, $Line) = (normalised_file($file), 0);
        return unless use_file($File);
        my $digest = $Structure->set_file($File);
        $Run{digests}{$File} ||= $digest;
        get_cover($cv, $root);
      },
      @require_trees,
    ) if @require_trees;
  }

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
      delete $Run{decision_inputs}{$file};
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
  $Structure->add_subroutine($File, [$Line, $Sub_name]) if $new;
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
    $c = [$c->[1] + $c->[2], $c->[3]];
  } elsif ($type eq "or_expr") {
    $c = [$c->[3], $c->[1] + $c->[2]];
  } else {
    $c = $Coverage->{branch}{$key} || [0, 0];
  }

  my ($n, $new) = $Structure->add_count("branch");
  $Structure->add_branch($file, [$line, { text => $text }]) if $new;
  my $ccount = $Run{count}{$file};
  if (exists $ccount->{branch}[$n]) {
    $ccount->{branch}[$n][$_] += $c->[$_] for 0 .. $#$c;
  } else {
    $ccount->{branch}[$n] = $c;
    my $vec = $Run{vec}{$File}{branch};
    vec($vec->{vec}, $vec->{size}++, 1) = ($_ ||= 0) ? 1 : 0 for @$c;
  }
}

sub _condition_counts ($c, $type, $op) {
  no warnings "uninitialized";

  if ($type eq "or" || $type eq "and") {
    my $const = _is_const_right($op->first->sibling);
    return ([$c->[3], $c->[1] + $c->[2]], 2, $c->[5] && !$const ? 1 : 0)
      if $c->[5] || $const;
    return ([$c->@[$type eq "or" ? (3, 2, 1) : (3, 1, 2)]], 3, 0);
  }
  if ($type eq "xor") {
    # !l&&!r  l&&!r  l&&r  !l&&r
    return ([$c->@[3, 2, 4, 1]], 4, 0);
  }
  die qq(Unknown type "$type" for conditional);
}

sub _condition_structure ($op, $strop, $left, $right, $left_op, $right_op) {
  my $key  = get_key($op);
  my $type = $op->name;
  $type =~ s/assign$//;
  $type = "or" if $type eq "dor";

  my ($c, $count, $void_collapsed)
    = _condition_counts($Coverage->{condition}{$key}, $type, $op);

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
    $void_collapsed ? (void_collapsed => 1) : (),
  };

  ($key, $structure, $c)
}

sub add_condition_cover (
  $op, $strop, $left, $right,
  $left_op = undef,
  $right_op = undef,
) {
  return unless $Collect && $Coverage{condition};

  my ($key, $structure, $c)
    = _condition_structure($op, $strop, $left, $right, $left_op, $right_op);

  my ($n, $new) = $Structure->add_count("condition");

  $Structure->add_condition($File, [$Line, $structure]) if $new;
  my $ccount = $Run{count}{$File};
  if (exists $ccount->{condition}[$n]) {
    $ccount->{condition}[$n][$_] += $c->[$_] // 0 for 0 .. $#$c;
  } else {
    $ccount->{condition}[$n] = $c;
    my $vec = $Run{vec}{$File}{condition};
    vec($vec->{vec}, $vec->{size}++, 1) = ($_ ||= 0) ? 1 : 0 for @$c;
  }

  _record_decision_inputs($key, $n);
}

sub _record_decision_inputs ($key, $n) {
  return unless $Coverage{mcdc};
  my $vectors = $Coverage->{decision_inputs}{$key} or return;
  my $di      = $Run{decision_inputs}{$File}[$n] //= {};
  $di->{$_} += $vectors->{$_} for keys %$vectors;
}

{
  no warnings "once";
  *is_scope       = \&B::Deparse::is_scope;
  *is_state       = \&B::Deparse::is_state;
  *is_ifelse_cont = \&B::Deparse::is_ifelse_cont;

  BEGIN {
    # B::Deparse has no pp_padrange - it handles padrange through lineseq
    # sequencing, never via direct dispatch.  When we call deparse() on
    # individual ops whose subtree contains a padrange, AUTOLOAD fires
    # with "unexpected OP_PADRANGE".  Return "" so the surrounding op
    # (aassign, entersub, etc.) still deparses correctly.
    *B::Deparse::pp_padrange = sub { "" }
      unless defined &B::Deparse::pp_padrange;

    # B::Deparse has no pp_custom - custom infix ops registered by XS modules
    # (e.g. Syntax::Operator::In) all dispatch through here. AUTOLOAD's default
    # behaviour warns and returns "XXX"; emit a quieter placeholder so
    # branch/condition labels stay readable.
    *B::Deparse::pp_custom = sub { "<custom op>" }
      unless defined &B::Deparse::pp_custom;
  }
}

sub _parse_pod_options {
  my %opts;
  if (ref $Coverage_options{pod}) {
    my $p;
    for ($Coverage_options{pod}->@*) {
      if (/^(?:package|(?:also_)?private|trustme|pod_from|nocp)$/) {
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
  return if !$gv || $gv->isa("B::SPECIAL") || $gv->STASH->isa("B::SPECIAL");

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
  $Structure->add_pod($File, [$Line, $Sub_name]) if $new;
  $Run{count}{$File}{pod}[$n] += $covered;
  my $vec = $Run{vec}{$File}{pod};
  vec($vec->{vec}, $n, 1) = $covered ? 1 : 0;
  $vec->{size} = $n + 1;
}

sub _want_cover_for {
  return if ${^GLOBAL_PHASE} eq "DESTRUCT";
  return unless defined $Sub_name;  # Only happens within Safe.pm, AFAIK
  return if length $File && !use_file($File);
  if (!$Self_cover_run && $File =~ /Devel\/Cover/) {
    # Allow partial self-coverage: if -select patterns are active and this DC
    # module matches one, let it through for instrumentation.
    return unless @Select_re && List::Util::any { defined && $File =~ $_ }
    @Select_re;
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

  my ($cc, $end_line) = _get_cover_walk($cv, $root);

  if ($sub_id && defined $cc) {
    $Structure->set_complexity($sub_id, $cc);
    $Structure->set_end_line($sub_id, $end_line) if defined $end_line;
  }
}

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
  and => ["and", 3, "&&", 11, "if"],
  or  => ["or",  2, "||", 10, "unless"],
  dor => ["//",  10],
);

sub _in_cond_expr_scope ($op) {
  my $p = _op_parent($op);
  return unless $p && $$p && $p->name eq "lineseq";
  my $gp = _op_parent($p);
  $gp && $$gp && ($gp->name eq "cond_expr" || $Seen{cond_expr}{$$gp})
}

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
  # Skip statements with no real successors (trailing braces etc.)
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
    # A dead COP - record only the location for this scope's conditions
    if (_in_cond_expr_scope($op)) {
      bless $op, "B::COP";
      get_location($op);
      $Current_cop = $op;
      # Stays blessed as B::COP for pragmata() - safe, the SV is mortal
      return;
    }
    bless $op, "B::COP";
    add_statement_cover($op) unless $Seen{statement}{$$op}++;
    bless $op, "B::$class";
  } else {
    return if _in_signature_argcheck($op);
    $Current_cop = $op;
    add_statement_cover($op) unless $Seen{statement}{$$op}++;
  }
}

sub _walk_elsif_chain ($cv, $false) {
  while (B::class($false) ne "NULL" && is_ifelse_cont($false)) {
    my $newop = $false->first;
    $Seen{cond_expr}{$$newop} = 1;
    my $newcond = $newop->first;
    my $newtrue = $newcond->sibling;
    if ($newcond->name eq "lineseq") {
      $newcond = $newcond->first->sibling;
    }
    $false = $newtrue->sibling;
    if ($Coverage{branch}) {
      my $newtext = _deparse_expr($cv, $newcond, 1, 0);
      add_branch_cover($newop, "elsif", "elsif ($newtext) { }", $File, $Line);
    }
  }
}

sub _walk_cond_expr ($cv, $op) {
  return unless $Collect;
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
    return unless $Coverage{branch};
    my $text = _deparse_expr($cv, $cond, 8, 0);
    add_branch_cover($op, "if", "$text ? :", $File, $Line);
  } else {
    if ($Coverage{branch}) {
      my $text = _deparse_expr($cv, $cond, 1, 0);
      add_branch_cover($op, "if", "if ($text) { }", $File, $Line);
    }
    _walk_elsif_chain($cv, $false);
  }
}

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

sub _lineseq_parent_cx ($parent) {
  my $gp = _op_parent($parent);
  return 0 unless $gp && $$gp;
  return 1 if $gp->name eq "cond_expr";
  return 1 if $Seen{cond_expr}{$$gp};
  0
}

sub _logop_parent_cx ($op, $highprec, $lowprec) {
  my $parent = _op_parent($op);
  return 0 unless $parent && $$parent;
  ($parent, my $early) = _skip_null_parents($parent, $highprec, $lowprec);
  return $early if defined $early;
  if ($parent && $$parent) {
    my $pname = $parent->name;
    return $highprec || $lowprec       if $pname eq "return";
    return 1                           if $pname eq "cond_expr";
    return _lineseq_parent_cx($parent) if $pname eq "lineseq";
    return 0 if $pname =~ /^(?:scope|leave(?:sub|try|loop)?|sort)$/;
    # B::Deparse recurses into logop children at cx=1
    return 1 if $pname =~ /^(?:and|or|dor)$/;
  }
  # Fall back to OPf_WANT for unrecognised parents
  my $want = $op->flags & OPf_WANT;
  return 0 unless $want >= B::OPf_WANT_SCALAR;
  $highprec || $lowprec
}

sub _is_loop_condition ($op) {
  my $p = _op_parent($op);
  return unless $p && $$p;
  $p = _op_parent($p) while $p && $$p && $p->name eq "null";
  $p && $$p && $p->name eq "leaveloop"
}

sub _resolve_blockname ($blockname, $cx) {
  return undef if $cx >= 1;
  if ($blockname) {
    $Shared_deparse ||= B::Deparse->new;
    return $Shared_deparse->keyword($blockname);
  }
  $blockname
}

sub _operand_is_decision ($op) {
  while ($op && $$op && ($op->name eq "null" || $op->name eq "not")) {
    return 0 unless $op->flags & OPf_KIDS;
    $op = $op->first;
  }
  $op && $$op && $Is_condition_op{ $op->name } ? 1 : 0
}

sub _record_logop_condition (
  $cv, $op, $strop, $left, $right, $prec, $use_dumper = 1,
) {
  my $l = _deparse_binop_left($cv, $op, $left, $prec, $use_dumper);
  my $r = _deparse_expr($cv, $right, $prec, $use_dumper);
  add_condition_cover($op, $strop, $l, $r, $left, $right)
    unless $Seen{condition}{$$op}++;
}

sub _record_compound_join ($cv, $op, $strop, $left, $right, $prec) {
  return unless _operand_is_decision($right);
  _record_logop_condition($cv, $op, $strop, $left, $right, $prec, 0);
}

sub _classify_op ($self, $op, $cx, $blockname) {
  my $is_statement
    = Has_op_statement() ? $op->private & OPpSTATEMENT() : $cx < 1
    && $blockname
    && $self->{expand} < 7;

  my $is_branch = $is_statement || ($cx < 1 && $blockname);

  ($is_statement, $is_branch)
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

  my $cx = _logop_parent_cx($op, $highprec, $lowprec);

  $blockname = _resolve_blockname($blockname, $cx);

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
    _record_compound_join(
      $cv,   $op,    $highop   // $lowop,
      $left, $right, $highprec // $lowprec,
    );
  } elsif ($cx > $lowprec && $highop) {
    _record_logop_condition($cv, $op, $highop, $left, $right, $highprec, 0);
  } elsif ($is_branch) {
    # From 5.43.8 OPpSTATEMENT routes statement-level expression joins here
    my $l    = _deparse_binop_left($cv, $op, $left, $lowprec);
    my $r    = _deparse_expr($cv, $right, $lowprec);
    my $type = $lowop eq "or" ? "or_expr" : $lowop;
    add_branch_cover($op, $type, "$l $lowop $r", $file, $line)
      unless $Seen{branch}{$$op}++;
    _record_compound_join(
      $cv,   $op,    $highop   // $lowop,
      $left, $right, $highprec // $lowprec,
    );
  } else {
    _record_logop_condition($cv, $op, $lowop, $left, $right, $lowprec);
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

Devel::Cover - Internals of the coverage collector

=head1 SYNOPSIS

  use Devel::Cover;

=head1 DESCRIPTION

This document describes the internals of the main Devel::Cover module for
people working on Devel::Cover itself.  The user documentation is in
F<Cover.pod>, which is what C<perldoc Devel::Cover> and MetaCPAN display.
Deeper design notes live in F<docs/technical/> in the distribution.

Coverage collection runs in three phases.

=over 4

=item * Compile time

L</import> parses the options, creates the coverage database, boots the XS
code in F<Cover.xs> and records which criteria to collect.  A C<CHECK>
block then runs L</check>, which finalises the criteria and announces the
run.

=item * Run time

The XS code counts op executions.  When it meets a new file it calls back
into L</use_file> to ask whether the file is of interest.  The Perl side is
otherwise idle while the program runs.

=item * End of run

L</report> runs from the last C<END> block.  It fetches the raw counts from
the XS side, walks every op tree, matches ops to source constructs using
C<B> and C<B::Deparse>, and writes the results to the coverage database.

=back

=head1 PACKAGE STATE

The configuration set by L</import> is held in file-scoped lexicals such as
C<$DB>, C<$Dir>, C<$Merge> and the select, ignore and inc lists, each of
which has a compiled regular expression counterpart.  The state shared
between phases is:

=over 4

=item C<%Files>

The cached result of L</use_file> for each file seen.  The XS code keeps a
direct handle on this hash and reads it on the fast path.

=item C<$File>, C<$Line>

The current source location while an op tree is walked.  Set by
L</get_location> and localised wherever a walk crosses into another file.

=item C<$Collect>

True while the walk callbacks should record what they find.

=item C<%Cvs>, C<@Cvs>, C<@Subs>

C<%Cvs> accumulates every CV that should be covered, keyed by stringified
B object.  L</check_files> flattens it into C<@Cvs>, sorted by line and
name, and keeps a reference to each sub in C<@Subs> so the subs still
exist at report time.

=item C<$Coverage>, C<$Structure>, C<%Run>

C<$Coverage> holds the raw counts fetched from the XS side at report time.
C<$Structure> is the L<Devel::Cover::DB::Structure> being built, recording
which constructs exist where.  C<%Run> collects everything written for
this run - counts, bit vectors, file digests and metadata.

=item C<%Seen>, C<%Parent_map>

C<%Seen> stops the same op being recorded twice for a criterion.
C<%Parent_map> maps each op's address to its parent op.  The XS walker
fills it in, giving parent lookups on every supported Perl version.

=back

=head1 LIFECYCLE

=head2 version

Return the module version.

=head2 has_select

True when any C<-select> pattern is active.  F<bin/cover> uses this to
decide whether partial self-coverage is in effect.

=head2 check

Run from a C<CHECK> block once the main program has compiled.  Takes a
first pass over the symbol table with L</check_files>, drops criteria that
cannot be collected - mcdc without condition, pod without a pod coverage
module - prints the banner and records run metadata with L</populate_run>.

=head2 first_init

A one-shot hook placed at the front of the C<INIT> queue by the XS
function C<set_first_init_and_end>.  Snapshots the C<INIT> block CVs via
C<collect_inits> so they can be covered at report time.

=head2 first_end

A one-shot hook placed at the front of the C<END> queue in the same way.
Calls C<set_last_end>, which appends L</last_end> to the C<END> queue and
snapshots the C<END> block CVs.  C<get_ends> returns both snapshots at
report time.

=head2 last_end

The final C<END> block of the program.  Calls L</report> if L</import>
ran.

=head2 CLONE

Refuse to work with threads.  Perl calls this when a new thread starts,
and it prints an apology and exits.

=head1 SET-UP

=head2 import ($class, @o)

The entry point for C<use Devel::Cover>.  Appends any options from
C<$DEVEL_COVER_OPTIONS>, parses them, arranges C<blib> handling, compiles
the select, ignore and inc patterns, bootstraps the XS code and
initialises the database and criteria.  A second call returns at once.
Under mod_perl the C<CHECK>-time work runs here instead, since mod_perl
compiles the module long after perl's own C<CHECK> phase.

=head2 _parse_options ($o, $blib)

Walk the option list, filling the scalar settings and the select, ignore
and inc lists.  A C<-> prefix on a list option resets the list before
adding and C<+> appends.  Unknown options warn and are skipped.

=head2 _init_db

Create the coverage database directory, untainting the paths, and delete
any existing database unless merging.

=head2 _init_coverage

Fill C<%Criteria> with each criterion's bit value from the XS constants,
split dash-separated criterion options such as C<pod-also_private-xx>, and
default to every criterion except C<time> when none was requested.

=head2 populate_run

Record metadata for this run - operating system, perl version, start time,
and the distribution name and version from F<MYMETA.json> or the directory
name.

=head1 CRITERIA

The XS side stores the active criteria as a bit mask.  These functions
translate between names and bits.

=head2 cover_names_to_val (@names)

Map criterion names to the combined bit mask, warning on unknown names.

=head2 set_coverage (@names)

Set the mask of criteria being collected.

=head2 add_coverage (@names)

Add criteria to the mask.

=head2 remove_coverage (@names)

Remove criteria from the mask.

=head2 get_coverage

Return the names of the criteria currently being collected, as a list or
as a space-joined string in scalar context.

=head1 FILE SELECTION

=head2 autosplit_parent ($file)

Strip the C<(autosplit into ...)> suffix AutoSplit appends to file names
and resolve stale F<blib> paths through C<%INC>, so coverage of autoloaded
subs is recorded against the parent module.

=head2 normalised_file ($file)

Return the canonical name for a file.  Eval prefixes are stripped,
module-relative paths are resolved against the directory the module was
compiled in, the absolute path is taken where that is safe, Windows
separators become C</>, the C<$Dir> prefix is removed and the digest store
is consulted so identical content is always reported under one name.
Results are cached, and a flag stops recursion when normalising itself
causes a module to load, as has happened with the Storable backend.

=head2 get_location ($op)

Set C<$File> and C<$Line> from a COP.  Eval file names of the form
C<< (eval n)[file:line] >> resolve to the real file, and the per-file
coverage vectors are primed the first time a file is seen.

=head2 use_file ($file)

Decide whether coverage should be collected for a file, caching the answer
in C<%Files>.  Eval and autosplit wrappings are unwrapped first.  The
select patterns are tried first, then the ignore patterns, then the inc
directories, and an unmatched file is used if it exists.  The XS code
calls this the first time each file is executed, so the cache matters.  It
also refreshes the CV list via L</add_cvs> in case the symbol table has
been manipulated since the last look.

=head2 check_file ($cv)

True when the file holding a CV's first statement is wanted.  A sub body
may open with prologue ops that carry no file information - a
C<methstart> for a class method, an C<introcv>/C<clonecv> pair for each
C<my sub> it encloses - so those are stepped past.

=head1 FINDING SUBROUTINES

A sub can only be covered if its CV is found.  Most CVs are reached by
walking the symbol table, but anonymous subs live only in pads, and a
wrapper such as a Moose method modifier may remove a named sub from its
glob entirely.  The pad walk recovers those.
F<docs/technical/wrapped-sub-coverage.md> discusses the approach and its
limits.

=head2 recoverable_sub ($cv)

True for a genuine named sub found through a reference.  Anonymous subs
and internal clones with generated names - a Moose C<:around> modifier's
CV, a pragma's C<BEGIN> block - share their body with a sub already found
the normal way and would be recorded twice.

=head2 ref_cvs ($sv, $seen, $depth = 1)

Collect named subs reachable from a pad slot through a reference -
directly to a CV, or one level deep through a plain array or hash.  That
is where a method modifier keeps the sub it replaced.  Descent stops
after one container so a wrapper's own deeper machinery is not reached.
Blessed containers are not descended, so a sub closing over an object
does not drag its whole graph in, and magical containers are not
descended because reading a tied one would run user code.  The seen hash
guards against cyclic structures.

=head2 pad_cvs ($cv, $seen = {})

Return the CVs found in a CV's pads, recursively.  A slot holding a CV
directly is an anonymous sub prototype, a slot holding a reference may
lead to a wrapped named sub, and a C<my sub> keeps its prototype in the
pad name's C<PROTOCV> (5.22+), the value slot being empty once its scope
has exited.  The seen hash stops loops from self-referential pad
entries.

=head2 B::GV::find_cv ($gv)

The per-glob callback for C<B::walksymtable>, defined in the C<B::GV>
package so the walker can call it as a method.  Records the glob's CV and
everything found in its pads.

=head2 sub_info ($cv)

Return a CV's name and the COP of its first statement, stepping past
C<methstart>, C<my sub> prologues and signature scaffolding.  A sub
enclosing a C<my sub> wraps its C<introcv>/C<clonecv> prologue in a
nested C<lineseq> before the first statement.  The prologue is identified
by its leading ops so ordinary nested blocks, which start with a
C<nextstate>, are left alone.  Used both for naming subs and for sorting
them.

=head2 add_cvs ($seen = {})

Record the CVs found in the main program's pads.

=head2 check_files

Build C<@Cvs> afresh.  Walks the symbol table with C<B::walksymtable>,
covering class C<ADJUST> blocks via the XS function C<adjust_blocks>, adds
pad CVs, then sorts by line and name.  A capture-free lexical sub appears
as both clone and prototype with the same start op, so doubles are
dropped.  Finally C<@Subs> takes a reference to each sub so none of them
is freed before report time.

=head2 special_block_cvs

Return the CVs of every C<BEGIN>, C<CHECK>, C<INIT> and C<END> block, for
the pad walk.

=head2 _seed_pad_cvs (@require_trees)

Feed pad-only anonymous subs from required files' top-level code and from
special blocks into C<%Cvs> before L</check_files> snapshots C<@Cvs>.

=head2 _seed_entered_subs

Feed the named subs recorded by the XS C<entersub> hook into C<%Cvs>
before L</check_files> snapshots C<@Cvs>.  These are the subs that ran but
may no longer be reachable from the symbol table or any pad - originals
displaced by a wrapper or freed by redefinition.  Filtered through
L</recoverable_sub> and L</check_file> like the pad-walk recoveries.

=head1 REPORTING

=head2 report

The driver run from L</last_end>.  Wraps L</_report> in an eval so a
failure while writing coverage does not change how the program exits, runs
it a second time under self-coverage to write Devel::Cover's own data, and
releases the required-file op trees held by the XS side.

=head2 _report

Do the real reporting work.  Fetches the raw counts with C<coverage(1)>,
seeds the pad CVs, then walks the main program, the special blocks, every
collected CV and the top-level code of each required file.  A file
required more than once (after C<delete $INC{...}>, say) captures one op
tree per compilation, each with distinct op addresses that C<%Seen>
cannot collapse, so only the newest tree per file is walked.  Top-level
require code has no C<set_subroutine> call, so the file context is
established explicitly before each tree or the per-file counters would
run against the wrong file.  Finally the
collected files are filtered and the database is written.  Runs with the
current directory set to C<$Dir> so relative names resolve as they did at
compile time.

=head2 _filter_cover_files

Drop collected data for files that fail L</use_file> and store the
per-file counts into the structure.

=head2 _write_coverage_db

Write this run's data under a unique subdirectory of F<runs/> in the
database, write the file digests and print the summary.  A self-coverage
first pass deletes its data instead, leaving only the second pass's view.

=head1 RECORDING COVERAGE

The C<add_*_cover> functions turn one op into a structure entry, recording
which construct exists at which line, and a run count, recording how often
each outcome ran.  Structure and counts are stored separately so separate
runs can merge.  The counts are keyed by C<get_key>, which identifies the
op in the raw XS data.

=head2 add_subroutine_cover ($op)

Record a subroutine as covered when its first statement ran.

=head2 add_statement_cover ($op)

Record a statement and its execution count, plus profiling time when the
C<time> criterion is active.

=head2 add_branch_cover ($op, $type, $text, $file, $line)

Record a two-way branch.  For the C<and>, C<or> and final C<elsif> types
the counts derive from the condition data, where the true path was taken
whenever the op did not short-circuit.  An C<and> may also be a plain
C<if> with no C<else>, an C<or> an C<unless>, and the C<elsif> form
applies when no further C<elsif> or C<else> follows.

=head2 _is_const_right ($op)

True when the right operand of a logical op is a constant-like expression
with a fixed truth value, unwrapping an enclosing C<sassign> first.  A
C<multiconcat> op (Perl 5.28+) counts when its literal text is truthy -
truthy rather than merely non-empty because C<"0"> is the one non-empty
string that is false.  Such an op collapses to a two-row condition
counting only the left operand.

=head2 _condition_counts ($c, $type, $op)

Reorder the raw XS condition counts into truth-table row order and return
the counts, the row count and a flag marking a genuine right operand
collapsed by void context, which MC/DC uses to rebuild the full decision.

=head2 _skip_to_condop ($op)

Descend through wrapper ops - C<null>, C<not>, scopes - to the logop
underneath that has its own condition entry, counting traversed C<not>
ops.

=head2 _resolve_child_op ($child_op)

Resolve a condition operand to the address of its underlying logop and a
negation flag, for linking nested decisions.

=head2 _condition_structure ($op, $strop, $left, $right, $left_op, $right_op)

Build the structure entry for a condition - its type and row count, the
deparsed operand texts, and the operand addresses and negation flags MC/DC
needs to join nested decisions into one.

=head2 add_condition_cover ($op, $strop, $left, $right, $left_op, $right_op)

Record a condition's truth-table counts and, when mcdc is active, its
evaluation vectors.

=head2 _record_decision_inputs ($key, $n)

Accumulate the MC/DC evaluation vectors the XS side gathered for a
condition.

=head2 _parse_pod_options

Turn the dash-separated C<pod> criterion options into the argument list
for the L<Pod::Coverage> constructor.

=head2 _add_pod_cover ($cv)

Ask L<Pod::Coverage> (or L<Pod::Coverage::CountParents>) whether the
current sub is documented and record the answer against the sub's line.

=head1 WALKING OP TREES

L</get_cover> drives the XS walker C<walk_ops> over one CV.  The walker
visits the interesting ops and dispatches to the C<_walk_*> callbacks
below, which classify each op and record it through the functions above.
Labels for the reports are produced with C<B::Deparse>, taking care to
match the precedence context (C<cx>) B::Deparse itself would use at that
point in a full deparse, so the text reads as it was written.

=head2 _want_cover_for

Decide whether the sub just located should be covered at all, filtering
out unwanted files and keeping Devel::Cover's own modules out of ordinary
runs while letting them through under self-coverage or an explicit
C<-select>.

=head2 _add_subroutine_structure ($cv, $start)

Register the sub with the structure, distinguishing several subs on one
line by a per-line count, and record subroutine and pod coverage.
Instances of anonymous subs on the same line are merged.

=head2 get_cover ($cv, $root = undef)

Collect coverage for one CV.  The main program and the top-level code of
required files have no C<ROOT> in their CVs, so the root op is passed
alongside.  Cyclomatic complexity and the last line seen are recorded
against the sub.

=head2 _with_deparse ($cv, $use_dumper, $code)

Run a deparsing callback against a shared C<B::Deparse> object prepared
for the CV, with pragmata from the current COP applied where supported,
and strip the unindent markers from the result.

=head2 _deparse_expr ($cv, $op, $cx, $use_dumper = 1)

Deparse one op at the given precedence context.

=head2 _deparse_binop_left ($cv, $op, $child, $prec, $use_dumper = 1)

Deparse the left child of a binary op via B::Deparse's own left-operand
path, avoiding spurious parentheses when left-associative ops of the same
precedence nest (the inner C<&&> in C<$a && $b && $c>).

=head2 _op_parent ($op)

Look up an op's parent in C<%Parent_map>.

=head2 _in_cond_expr_scope ($op)

True for a null statement inside the condition scope of a C<cond_expr> or
C<elsif> - a dead COP created by the compiler, not a source statement.

=head2 _in_signature_argcheck ($op)

True for a C<nextstate> inside a signature's argument-checking block with
no default-value sibling.  Plain parameter bookkeeping is skipped, while a
default value is real conditional code.  The default-value op is an
C<argdefelem> under an C<argelem> from 5.38, or a C<paramtest> under a
C<null> from 5.43.4.

=head2 _walk_statement ($op, $type)

Record a statement, skipping ops with no real successors, dead COPs in
condition scopes and signature bookkeeping.  Also keeps C<$Current_cop> up
to date so deparsing sees the right pragmata and location.

=head2 _walk_elsif_chain ($cv, $false)

Follow the false arms of an C<if> statement through its C<elsif> chain,
recording a branch for each C<elsif> condition and marking the underlying
ops as seen so they are not recorded again as plain conditionals.

=head2 _walk_cond_expr ($cv, $op)

Record a C<cond_expr> - either a ternary or an C<if> statement.  On Perls
with C<OPpSTATEMENT> the op itself says which form it is.  Older Perls
fall back to structural heuristics in the style of B::Deparse.  Statement
form records an C<if> branch and walks the elsif chain, expression form
records a ternary branch.

=head2 _skip_null_parents ($parent, $highprec, $lowprec)

Step upwards through C<null> ops when determining context, stopping at
block boundaries and C<return>.

=head2 _lineseq_parent_cx ($parent)

Context for a logop under a C<lineseq> - expression context when the
lineseq belongs to a C<cond_expr> or C<elsif> wrapper, statement context
otherwise.  The last C<elsif> arm compiles to a logop rather than a
C<cond_expr>, so those wrappers are tracked in C<%Seen> and count too.

=head2 _logop_parent_cx ($op, $highprec, $lowprec)

Determine the precedence context for a logop by walking up the parent
chain, mirroring how B::Deparse's own recursion would arrive at the op.
C<OPf_WANT> alone cannot answer this, since it diverges from the deparse
context for C<return> (want C<NONE>, deparse cx 6) and for C<sort>,
C<map> and C<grep> blocks (want C<SCALAR>, deparse cx 0).  Parents the
walk does not recognise, such as nested logops where the optimiser
removed the C<cond_expr>, fall back to C<OPf_WANT>.

=head2 _is_loop_condition ($op)

True when a logop is the condition of a loop, which is always a branch.

=head2 _resolve_blockname ($blockname, $cx)

Return the keyword form of a statement-level logop's block name - C<if>
or C<unless> - or undef in expression context.

=head2 _operand_is_decision ($op)

True when an operand is itself a logop, looking through C<null> and
C<not> wrappers only.

=head2 _record_logop_condition ($cv, $op, $strop, $left, $right, $prec)

Deparse both operands and record the condition, once per op.

=head2 _record_compound_join ($cv, $op, $strop, $left, $right, $prec)

Record a statement-level join whose right operand is itself a decision,
so a compound decision keeps its root.  See
L<Devel::Cover::DB/Compound decision roots>.

=head2 _classify_op ($self, $op, $cx, $blockname)

Return whether a logop is in statement form, which controls the deparse
format, and whether it is a branch, which controls the coverage
classification.  A statement-level expression logop such as C<$y && $x++>
is a branch even though it is not in statement form.

=head2 _walk_logop ($cv, $op)

Classify an C<and>, C<or> or C<dor> op and record it.  A statement-form
op - an C<if> or C<unless> written as a modifier or block - is a branch.
An expression op in a higher-precedence position is recorded as a C<&&>,
C<||> or C<//> condition, one in statement position with a discarded
value is a branch, and anything else is a low-precedence C<and>/C<or>
condition.  Loop conditions are always branches.

=head2 _walk_logassignop ($cv, $op)

Record C<&&=>, C<||=> and C<//=> as conditions.

=head2 _walk_xor ($cv, $op)

Record C<xor> - and on 5.40+ C<^^> - as a four-row condition.

=head2 _get_cover_walk ($cv, $root)

Run the XS walker over a CV's op tree, dispatching each visited op to the
walk callbacks.  Returns the cyclomatic complexity, counted as decisions
plus one, and the highest line seen, used as the sub's end line.

=head1 PROGRESS OUTPUT

=head2 _report_progress ($msg, $code, @items)

Run a callback over a list of items, printing percentage progress on a
terminal and the time taken in any case.

=head2 get_cover_progress ($type, @cvs)

Run L</get_cover> over a list of CVs with progress output.

=head1 XS INTERFACE

F<Cover.xs> is loaded by L</import> via C<bootstrap> and provides the
low-level machinery.  The functions used from this module are:

=over 4

=item C<set_criteria>, C<add_criteria>, C<remove_criteria>, C<get_criteria>

Maintain the bit mask of criteria being collected.

=item C<coverage_*>

The bit value for each criterion, plus C<coverage_all> and
C<coverage_none>.

=item C<coverage ($final)>

The raw collected data.  A true argument finalises pending data for
reporting.

=item C<get_key ($op)>

The key identifying an op in the raw data.

=item C<get_elapsed>

Elapsed run time in microseconds.

=item C<walk_ops ($root, $callback, $cv, $parent_map)>

The op tree walker driving L</_get_cover_walk>, filling C<%Parent_map> as
it goes.

=item C<set_first_init_and_end>, C<collect_inits>, C<set_last_end>, C<get_ends>

Bookkeeping for special blocks.  The first three arrange the hooks
described under L</first_init>, and C<get_ends> returns the snapshotted
C<INIT> and C<END> block CVs for coverage.

=item C<get_require_trees>, C<release_require_trees>

The top-level op trees of required files, kept alive by the XS
C<leaveeval> hook so their statements can be covered, and released once
reporting is done.

=item C<get_entered_subs>

The named subs recorded as they were entered, as C<B::CV> objects.  The
XS C<entersub> hook keeps a strong reference to each, so a sub displaced
from the symbol table or freed by redefinition can still be covered.  See
F<docs/technical/wrapped-sub-coverage.md>.

=item C<adjust_blocks ($stash)>

References to a class's C<ADJUST> block CVs (Perl 5.38+), which live
outside the symbol table.

=back

In the other direction the XS code calls back into L</use_file> while the
program runs, installs L</first_init>, L</first_end> and L</last_end> as
C<INIT> and C<END> blocks, and calls L</report> directly before an C<exec>
replaces the process.

=head1 SEE ALSO

=over 4

=item * L<Devel::Cover> - the user documentation

=item * F<docs/technical/> - design notes on branch and condition
handling, MC/DC, self-coverage and more

=item * L<Devel::Cover::DB::Structure>

=back

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

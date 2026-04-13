# Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::DB;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use Devel::Cover::Criterion ();
use Devel::Cover::DB::File  ();
use Devel::Cover::DB::IO    ();

use Carp         qw( carp croak );
use File::Find   qw( find );
use File::Path   qw( rmtree );
use List::Util   qw( any );
use Scalar::Util qw( blessed reftype );

use Devel::Cover::Dumper qw( Dumper );  # For debugging

my $Has_term_size = eval { require Term::Size };

my $DB = "cover.15";                    # Version of the database

@Devel::Cover::DB::Criteria
  = (qw( statement branch path condition subroutine pod time ));
@Devel::Cover::DB::Criteria_short   = (qw( stmt bran path cond sub pod time ));
$Devel::Cover::DB::Ignore_filenames = qr/   # Used by Devel::Cover
  (?: [\/\\]lib[\/\\](?:Storable|POSIX).pm$ )
  | # Moose
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
  | # perl generated
  (?: \/loader\/0x )
/x;

sub new ($class, %o) {
  my $self = {
    criteria         => \@Devel::Cover::DB::Criteria,
    criteria_short   => \@Devel::Cover::DB::Criteria_short,
    runs             => {},
    files            => [],
    collected        => {},
    uncoverable_file => [],
    %o,
  };

  $self->{all_criteria}         = [ $self->{criteria}->@*,       "total" ];
  $self->{all_criteria_short}   = [ $self->{criteria_short}->@*, "total" ];
  $self->{base}               ||= $self->{db};
  bless $self, $class;

  if (defined $self->{db}) {
    $self->validate_db;
    my $file = "$self->{db}/$DB";
    $self->read($file) if -e $file;
  }

  $self
}

sub criteria           ($self) { $self->{criteria}->@* }
sub criteria_short     ($self) { $self->{criteria_short}->@* }
sub all_criteria       ($self) { $self->{all_criteria}->@* }
sub all_criteria_short ($self) { $self->{all_criteria_short}->@* }
sub files              ($self) { $self->{files}->@* }

sub read ($self, $file) {
  my $io = Devel::Cover::DB::IO->new;
  my $db = eval { $io->read($file) };
  if ($@ || !$db) {
    warn $@;
  } else {
    $self->{runs}  = $db->{runs};
    $self->{files} = $db->{files} // [];
  }
  $self
}

sub write ($self, $db = undef) {
  $self->{db} = $db if defined $db;

  croak "No db specified" unless length $self->{db};
  unless (mkdir $self->{db}) {
    croak "Can't mkdir $self->{db}: $!\n" unless -d $self->{db};
  }
  chmod 0777, $self->{db} if $self->{loose_perms};
  $self->validate_db;

  my $data = { runs => $self->{runs}, files => $self->{files} };
  my $io   = Devel::Cover::DB::IO->new;
  $io->write($data, "$self->{db}/$DB");
  $self->{structure}->write($self->{base}) if $self->{structure};
  $self
}

sub delete ($self, $db = undef) {
  $db         //= $self->{db} if ref $self;
  $db         //= "";
  $self->{db}   = $db if ref $self;
  croak "No db specified" unless length $db;

  return $self unless -d $db;

  # TODO - just delete the directory?
  opendir my $dir, $db or die "Can't opendir $db: $!";
  my @files = map "$db/$_", map /(.*)/ && $1, grep !/^\.\.?/, readdir $dir;
  closedir $dir or die "Can't closedir $db: $!";
  rmtree(\@files) if @files;

  $self
}

sub clean ($self) {
  # remove all lock files
  my $rm_lock = sub { unlink if /\.lock$/ };
  find($rm_lock, $self->{db});
}

sub merge_runs ($self) {
  my $db = $self->{db};
  return $self unless length $db;
  opendir my $dir, "$db/runs" or return $self;
  my @runs = map "$db/runs/$_", grep !/^\.\.?/, readdir $dir;
  closedir $dir or die "Can't closedir $db/runs: $!";

  $self->{changed_files} = {};

  # The ordering is important here.  The runs need to be merged in the order
  # they were created.  Run names use microsecond timestamps so lexicographic
  # sorting matches chronological order.

  for my $run (sort @runs) {
    my $r = Devel::Cover::DB->new(base => $self->{base}, db => $run);
    $self->merge($r);
  }

  $self->write($db) if @runs;
  rmtree(\@runs);

  if (keys $self->{changed_files}->%*) {
    require Devel::Cover::DB::Structure;
    my $st = Devel::Cover::DB::Structure->new(base => $self->{base});
    $st->read_all;
    for my $file (sort keys $self->{changed_files}->%*) {
      $st->delete_file($file);
    }
    $st->write($self->{base});
  }

  $self->clean;

  $self
}

sub validate_db ($self) {
  # Check validity of the db.  It is valid if the $DB file is there, or if it
  # is not there but the db directory is empty, or if there is no db directory.
  # die if the db is invalid.

  # just warn for now
  print STDERR "Devel::Cover: $self->{db} is an invalid database\n"
    unless $self->is_valid;

  $self
}

sub exists ($self) { -d $self->{db} }

sub is_valid ($self) {
  return 1 if !-e $self->{db};
  return 1 if -e "$self->{db}/$DB";
  opendir my $dir, $self->{db} or return 0;
  my $ignore = join "|", qw( runs structure debuglog digests .AppleDouble );
  for my $file (readdir $dir) {
    next if $file eq "." || $file eq "..";
    next if $file =~ /(?:$ignore)|(?:\.lock)$/ && -e "$self->{db}/$file";
    warn "found $file in $self->{db}";
    return 0;
  }
  closedir $dir
}

sub collected ($self) {
  $self->cover;
  sort keys $self->{collected}->%*
}

sub merge ($self, $from) {
  for my $fname (sort keys $from->{runs}->%*) {
    my $frun = $from->{runs}{$fname};
    for my $file (sort keys $frun->{digests}->%*) {
      my $digest = $frun->{digests}{$file};
      for my $name (sort keys $self->{runs}->%*) {
        my $run = $self->{runs}{$name};
        if (
             $run->{digests}{$file}
          && $digest
          && $run->{digests}{$file} ne $digest
        ) {
          # File has changed.  Delete old coverage instead of merging.
          print STDOUT "Devel::Cover: Deleting old coverage for ",
            "changed file $file\n"
            unless $Devel::Cover::Silent;
          delete $run->{digests}{$file};
          delete $run->{count}{$file};
          delete $run->{vec}{$file};
          $self->{changed_files}{$file}++;
        }
      }
    }
  }

  _merge_hash($self->{runs},      $from->{runs});
  _merge_hash($self->{collected}, $from->{collected});

  # TODO - determine whether, when the database gets big, it's quicker to
  # merge into what's already there.  Instead of the previous two lines we
  # would have these:

  # _merge_hash($from->{runs},      $self->{runs});
  # _merge_hash($from->{collected}, $self->{collected});
  # for (keys %$self) {
  # $from->{$_} = $self->{$_} unless $_ eq "runs" || $_ eq "collected";
  # }
  # $_[0] = $from;
}

sub _merge_hash ($into, $from, $noadd = 0) {
  return unless $from;
  for my $fkey (keys %$from) {
    my $fval = $from->{$fkey};

    if (defined $into->{$fkey} && (reftype($into->{$fkey}) // "") eq "ARRAY") {
      _merge_array($into->{$fkey}, $fval, $noadd);
    } elsif (defined $fval && (reftype($fval) // "") eq "HASH") {
      if (defined $into->{$fkey} && (reftype($into->{$fkey}) // "") eq "HASH") {
        _merge_hash($into->{$fkey}, $fval, $noadd);
      } else {
        $into->{$fkey} = $fval;
      }
    } else {
      # A scalar (or a blessed scalar).  We know there is no into array, or we
      # would have just merged with it.
      $into->{$fkey} = $fval;
    }
  }
}

sub _merge_array ($into, $from, $noadd = 0) {
  for my $i (@$into) {
    my $f  = shift @$from;
    my $it = reftype($i) // "";
    my $ft = reftype($f) // "";
    if ($it eq "ARRAY" || !defined $i && $ft eq "ARRAY") {
      _merge_array($i, $f || [], $noadd);
    } elsif ($it eq "HASH" || !defined $i && $ft eq "HASH") {
      _merge_hash($i, $f || {}, $noadd);
    } elsif ($it eq "SCALAR" || !defined $i && $ft eq "SCALAR") {
      $$i += $$f;
    } else {
      if (defined $f) {
        $i ||= 0;
        if (!$noadd && $f =~ /^\d+$/ && $i =~ /^\d+$/) {
          $i += $f;
        } elsif ($i ne $f) {
          warn "<$i> does not match <$f> - using latter value";
          $i = $f;
        }
      }
    }
  }
  push @$into, @$from;
}

sub summary ($self, $file, $criterion = undef, $part = undef) {
  my $f = $self->{summary}{$file};
  return $f unless $f && defined $criterion;
  my $c = $f->{$criterion};
  $c && defined $part ? $c->{$part} : $c
}

sub _sub_coverage ($file_obj, $start, $end) {
  my ($covered, $total) = (0, 0);
  for my $name (qw( statement branch condition )) {
    my $crit = $file_obj->{$name} or next;
    for my $line ($start .. $end) {
      my $loc = $crit->{$line} or next;
      for my $obj (@$loc) {
        my $t = $obj->total;
        $total   += $t;
        $covered += $t - $obj->error;
      }
    }
  }
  $total ? 100 * $covered / $total : 100
}

sub _crap ($cc, $cov_pct) {
  $cc**2 * (1 - $cov_pct / 100)**3 + $cc
}

sub _file_coverage ($s_file) {
  my ($covered, $total) = (0, 0);
  for my $name (qw( statement branch condition )) {
    my $c = $s_file->{$name} or next;
    $total   += $c->{total} || 0;
    $covered += ($c->{total} || 0) - ($c->{error} || 0);
  }
  $total ? 100 * $covered / $total : 100
}

sub summarise_complexity ($self, $s, $files) {
  my $st = $self->{_structure} or return;
  my ($total_sum, $total_count, $total_max)                = (0, 0, 0);
  my ($crap_total_sum, $crap_total_count, $crap_total_max) = (0, 0, 0);
  my ($fcrap_total_sum, $fcrap_total_count)                = (0, 0);
  for my $file (@$files) {
    my $file_obj = $self->cover->get($file);
    my $digest   = $file_obj->{meta}{digest};
    next unless $digest;
    my $cc_hash  = $st->get_complexity($digest) or next;
    my $end_hash = $st->get_end_lines($digest) || {};
    my ($max, $sum, $count)                = (0, 0, 0);
    my ($crap_max, $crap_sum, $crap_count) = (0, 0, 0);
    my @subs;

    for my $line (sort { $a <=> $b } keys %$cc_hash) {
      for my $sub_name (sort keys %{ $cc_hash->{$line} }) {
        my $cc_arr  = $cc_hash->{$line}{$sub_name};
        my $end_arr = $end_hash->{$line}{$sub_name} // [];
        for my $scount (0 .. $#$cc_arr) {
          my $cc = $cc_arr->[$scount];
          next unless defined $cc;
          $max  = $cc if $cc > $max;
          $sum += $cc;
          $count++;
          my $end  = $end_arr->[$scount] // $line;
          my $cov  = _sub_coverage($file_obj, $line, $end);
          my $crap = _crap($cc, $cov);
          $crap_max  = $crap if $crap > $crap_max;
          $crap_sum += $crap;
          $crap_count++;
          push @subs, {
              name => $sub_name,
              line => $line + 0,
              cc   => $cc,
              cov  => $cov,
              crap => $crap,
            };
        }
      }
    }
    next unless $count;
    $s->{$file}{complexity}
      = { max => $max, mean => $sum / $count, count => $count };
    my $file_cc   = $sum - $count + 1;
    my $file_cov  = _file_coverage($s->{$file});
    my $file_crap = _crap($file_cc, $file_cov);
    $s->{$file}{crap} = {
      max       => $crap_max,
      mean      => $crap_sum / $crap_count,
      count     => $crap_count,
      subs      => \@subs,
      file_cc   => $file_cc,
      file_cov  => $file_cov,
      file_crap => $file_crap,
    };
    $fcrap_total_sum += $file_crap;
    $fcrap_total_count++;
    $total_max         = $max if $max > $total_max;
    $total_sum        += $sum;
    $total_count      += $count;
    $crap_total_max    = $crap_max if $crap_max > $crap_total_max;
    $crap_total_sum   += $crap_sum;
    $crap_total_count += $crap_count;
  }
  if ($total_count) {
    $s->{Total}{complexity} = {
      max   => $total_max,
      mean  => $total_sum / $total_count,
      count => $total_count,
    };
  }
  if ($crap_total_count) {
    $s->{Total}{crap} = {
      max       => $crap_total_max,
      mean      => $crap_total_sum / $crap_total_count,
      count     => $crap_total_count,
      file_crap => $fcrap_total_count
      ? $fcrap_total_sum / $fcrap_total_count
      : 0,
    };
  }
}

sub calculate_summary ($self, %options) {
  return if exists $self->{summary} && !$options{force};
  my $s = $self->{summary} = {};

  my @files = $self->cover->items;
  if (my $files = delete $options{files}) {
    my %required_files = map { $_ => 1 } @$files;
    @files = grep $required_files{$_}, @files;
  }

  for my $file (@files) {
    $self->cover->get($file)->calculate_summary($self, $file, \%options);
  }

  for my $file (@files) {
    $self->cover->get($file)->calculate_percentage($self, $s->{$file});
  }

  my $t = $self->{summary}{Total};
  for my $criterion ($self->criteria) {
    next unless exists $t->{$criterion};
    my $c = "Devel::Cover::\u$criterion";
    $c->calculate_percentage($self, $t->{$criterion});
  }
  Devel::Cover::Criterion->calculate_percentage($self, $t->{total});

  $self->summarise_complexity($s, \@files);
}

sub trimmed_file ($f, $len) {
  substr $f, 0, 3 - $len, "..." if length $f > $len;
  $f
}

sub print_summary ($self, $files = undef, $criteria = undef, $opts = {}) {
  my %crit    = map { $_ => 1 } $self->collected;
  my %options = $criteria ? map { $_ => 1 } grep $crit{$_}, @$criteria : %crit;
  $options{total} = 1 if keys %options;

  my $n = keys %options;

  $options{files} = $files if $files && @$files;
  $self->calculate_summary(%options, %$opts);

  my $format = sub ($part, $criterion) {
    $options{$criterion} && exists $part->{$criterion}
      ? do {
        my $x = sprintf "%5.2f", $part->{$criterion}{percentage};
        chop $x;
        $x
      }
      : "n/a"
  };

  my $s     = $self->{summary};
  my @files = (grep($_ ne "Total", sort keys %$s), "Total");
  my $max   = 5;
  require Devel::Cover::Path;
  my ($prefix, $short) = Devel::Cover::Path::common_prefix(@files);

  for (@files) { $max = length $short->{$_} if length $short->{$_} > $max }

  my $width
    = !$ENV{DEVEL_COVER_TEST_SUITE}
    && $Has_term_size
    && -t STDOUT ? (Term::Size::chars(\*STDOUT))[0] : 80;
  my $fw = $width - $n * 7 - 3;

  $fw = $max if $max < $fw;

  no warnings "uninitialized";
  my $fmt = "%-${fw}s" . " %6s" x $n . "\n";

  printf STDOUT "\nCommon prefix: %s\n\n", $prefix if $prefix;
  printf STDOUT $fmt,                      "-" x $fw, ("------") x $n;
  printf STDOUT $fmt, "File", map $self->{all_criteria_short}[$_],
    grep $options{ $self->{all_criteria}[$_] }, 0 .. $self->{all_criteria}->$#*;
  printf STDOUT $fmt, "-" x $fw, ("------") x $n;

  my $has_uncompiled;
  for my $file (@files) {
    my $uncompiled
      = $file ne "Total" && $self->cover->file($file)->{meta}{uncompiled};
    $has_uncompiled ||= $uncompiled;
    printf STDOUT $fmt, trimmed_file($short->{$file}, $fw),
      $uncompiled
      ? ("n/a") x $n
      : (
        map $format->($s->{$file}, $_),
        grep $options{$_},
        $self->{all_criteria}->@*,
      );
  }

  printf STDOUT $fmt, "-" x $fw, ("------") x $n;
  if ($has_uncompiled && !eval { require PPI; 1 }) {
    printf STDOUT "\n%s\n",
      "n/a: install PPI for estimated coverage of untested files";
  }
  print STDOUT "\n\n";
}

sub add_statement ($self, $cc, $sc, $fc, $uc) {
  my %line;
  for my $i (0 .. $#$fc) {
    my $l = $sc->[$i] // do {
      warn "Devel::Cover: ignoring extra statement\n";
      return;
    };
    my $n = $line{$l}++;
    no warnings "uninitialized";
    $cc->{$l}[$n][0]  += $fc->[$i];
    $cc->{$l}[$n][1] ||= $uc->{$l}[$n][0][1];
  }
}

sub add_time ($self, $cc, $sc, $fc, $) {
  my %line;
  for my $i (0 .. $#$fc) {
    my $l = $sc->[$i] // do {
      warn "Devel::Cover: ignoring extra statement\n";
      return;
    };
    my $n = $line{$l}++;
    $cc->{$l}[$n] ||= do { my $c; \$c };
    no warnings "uninitialized";
    $cc->{$l}[$n]->$* += $fc->[$i];
  }
}

sub add_branch ($self, $cc, $sc, $fc, $uc) {
  my %line;
  for my $i (0 .. $#$fc) {
    my $l = $sc->[$i][0] // do {
      warn "Devel::Cover: ignoring extra branch\n";
      return;
    };
    my $n = $line{$l}++;
    no warnings "uninitialized";
    if (my $a = $cc->{$l}[$n]) {
      $a->[0][0] += $fc->[$i][0];
      $a->[0][1] += $fc->[$i][1];
      $a->[0][2] += $fc->[$i][2] if exists $fc->[$i][2];
      $a->[0][3] += $fc->[$i][3] if exists $fc->[$i][3];
    } else {
      $cc->{$l}[$n] = [ $fc->[$i], $sc->[$i][1] ];
    }
    $cc->{$l}[$n][2][ $_->[0] ] ||= $_->[1] for @{ $uc->{$l}[$n] };
  }
}

sub add_subroutine ($self, $cc, $sc, $fc, $uc) {
  # $cc = { line_number => [ [ count, sub_name, uncoverable ], [ ... ] ], .. }
  # $sc = [ [ line_number, sub_name ], [ ... ] ]
  # $fc = [ count, ... ]
  # $uc = { line_number => [ [ ??? ], [ ... ] ], ... }
  # length @$sc == length @$fc

  my %line;
  for my $i (0 .. $#$fc) {
    my $l = $sc->[$i][0] // do {
      warn "Devel::Cover: ignoring extra subroutine\n";
      return;
    };

    my $n = $line{$l}++;
    if (my $a = $cc->{$l}[$n]) {
      no warnings "uninitialized";
      $a->[0] += $fc->[$i];
    } else {
      $cc->{$l}[$n] = [ $fc->[$i], $sc->[$i][1] ];
    }
    $cc->{$l}[$n][2] ||= $uc->{$l}[$n][0][1];
  }
}

{
  no warnings "once";
  *add_condition = \&add_branch;
  *add_pod       = \&add_subroutine;
}

sub uncoverable_files ($self) {
  my $f = ".uncoverable";
  ($self->{uncoverable_file}->@*, $f, glob "~/$f")
}

sub uncoverable ($self) {
  my $u = {};  # holds all the uncoverable information

  # First populate $u with the uncoverable information directly from the
  # .uncoverable files.  Then loop through the information converting it to the
  # format we will use later to manage the uncoverable code.  The primary
  # changes are converting MD5 digests of lines to line numbers, and converting
  # filenames to MD5 digests of the files.

  for my $file ($self->uncoverable_files) {
    open my $f, "<", $file or next;
    print STDOUT "Reading uncoverable information from $file\n"
      unless $Devel::Cover::Silent;
    while (<$f>) {
      chomp;
      my ($file, $crit, $line, $count, $type, $class, $note) = split " ", $_, 7;
      push $u->{$file}{$crit}{$line}[$count]->@*, [ $type, $class, $note ];
    }
  }

  # Now change the format of the uncoverable information
  for my $file (sort keys %$u) {
    open my $fh, "<", $file or do {
      warn "Devel::Cover: Can't open $file: $!\n";
      next;
    };
    my $df = Digest::MD5->new;  # MD5 digest of the file
    my %dl;                     # maps MD5 digests of lines to line numbers
    my $ln = 0;                 # line number
    while (<$fh>) {
      $dl{ Digest::MD5->new->add($_)->hexdigest } = ++$ln;
      $df->add($_);
    }
    close $fh or warn "Devel::Cover: Can't close $file: $!\n";
    my $f = $u->{$file};
    for my $crit (keys %$f) {
      my $c = $f->{$crit};
      for my $line (keys %$c) {
        if (exists $dl{$line}) {
          # Change key from the MD5 digest to the actual line number
          $c->{ $dl{$line} } = delete $c->{$line};
        } else {
          warn "Devel::Cover: Can't find line for uncovered data: "
            . "$file $crit $line\n";
          delete $c->{$line};
        }
      }
    }
    # Change the key from the filename to the MD5 digest of the file
    $u->{ $df->hexdigest } = delete $u->{$file};
  }

  print STDERR Dumper $u;
  $u
}

sub add_uncoverable ($self, $adds) {
  for my $add (@$adds) {
    my ($file, $crit, $line, $count, $type, $class, $note) = split " ", $_, 7;
    my ($uncoverable_file) = $self->uncoverable_files;

    open my $f, "<", $file or do {
      warn "Devel::Cover: Can't open $file: $!";
      next;
    };
    while (<$f>) {
      last if $. == $line;
    }
    if (defined) {
      open my $u, ">>", $uncoverable_file
        or die "Devel::Cover: Can't open $uncoverable_file: $!\n";
      my $dl = Digest::MD5->new->add($_)->hexdigest;
      print $u "$file $crit $dl $count $type $class $note\n";
    } else {
      warn "Devel::Cover: Can't find line $line in $file.  ",
        "Last line is $.\n";
    }
    close $f or die "Devel::Cover: Can't close $file: $!\n";
  }
}

sub delete_uncoverable ($self, $deletes) {
}

sub clean_uncoverable ($self) {
}

sub uncoverable_comments ($self, $uncoverable, $file, $digest) {
  my $cr    = join "|", $self->{all_criteria}->@*;
  my $uc    = qr/(.*)# uncoverable ($cr)(.*)/;  # regex for uncoverable comments
  my %types = (
    branch    => { true => 0, false => 1 },
    condition => { left => 0, right => 1, false => 2 },
  );

  # Look for uncoverable comments
  open my $fh, "<", $file or do {
    # The warning should have already been given ...
    # warn "Devel::Cover: Warning: can't open $file: $!\n";
    return;
  };
  my @waiting;
  while (<$fh>) {
    chomp;
    next unless /$uc/ || @waiting;
    if ($2) {
      my ($code, $criterion, $info) = ($1, $2, $3);
      my ($count, $class, $note, $type) = (1, "default", "");

      if ($criterion eq "branch" || $criterion eq "condition") {
        if ($info =~ /^\s*(\w+)(?:\s|$)/) {
          my $t = $1;
          $type = $types{$criterion}{$t};
          unless (defined $type) {
            warn "Unknown type $t found parsing "
              . "uncoverable $criterion at $file:$.\n";
            $type = 999;  # partly magic number
          }
        }
      }
      # e.g.: count:1 | count:2,5 | count:1,4..7
      my $c = qr/\d+(?:\.\.\d+)?/;
      $count = $1 if $info =~ /count:($c(?:,$c)*)/;
      my @counts = map { m/^(\d+)\.\.(\d+)$/ ? ($1 .. $2) : $_ } split m/,/,
        $count;
      if ($info =~ /class:(\w+)/) { $class = $1 }
      if ($info =~ /note:(.+)/)   { $note  = $1 }

      for my $c (@counts) {
        # no warnings "uninitialized";
        # warn "pushing $criterion, $c - 1, $type, $class, $note";
        push @waiting, [ $criterion, $c - 1, $type, $class, $note ];
      }

      next unless $code =~ /\S/;
    }

    # found what we are waiting for
    while (my $w = shift @waiting) {
      my ($criterion, $count, $type, $class, $note) = @$w;
      push $uncoverable->{$digest}{$criterion}{$.}[$count]->@*,
        [ $type, $class, $note ];
    }
  }
  close $fh or warn "Devel::Cover: Can't close $file: $!\n";

  warn scalar @waiting,
    " unmatched uncoverable comments not found at end of $file\n"
    if @waiting;

  # TODO - read in and merge $self->uncoverable;
  # print Dumper $uncoverable;
}

sub objectify_cover ($self) {
  unless (
    blessed($self->{cover})
    && $self->{cover}->isa("Devel::Cover::DB::Cover")
  ) {
    bless $self->{cover}, "Devel::Cover::DB::Cover";
    for my $file (values $self->{cover}->%*) {
      bless $file, "Devel::Cover::DB::File";
      while (my ($crit, $criterion) = each %$file) {
        next if $crit eq "meta";  # ignore meta data
        my $class = "Devel::Cover::" . ucfirst lc $crit;
        bless $criterion, "Devel::Cover::DB::Criterion";
        for my $line (values %$criterion) {
          for my $o (@$line) {
            die "<$crit:$o>" unless ref $o;
            bless $o, $class;
            bless $o, $class . "_" . $o->type if $o->can("type");
          }
        }
      }
    }
    for my $r (keys $self->{runs}->%*) {
      if (defined $self->{runs}{$r}) {
        bless $self->{runs}{$r}, "Devel::Cover::DB::Run";
      } else {
        delete $self->{runs}{$r};  # DEVEL_COVER_SELF
      }
    }
  }

  unless (exists &Devel::Cover::DB::Base::items) {
    *Devel::Cover::DB::Base::items = sub ($self) { keys %$self };

    {
      no warnings "once";
      *Devel::Cover::DB::Base::values = sub ($self) { values %$self };
      *Devel::Cover::DB::Base::get    = sub ($self, $get) { $self->{$get} };
    }

    my $classes = {
      Cover     => [qw( files     file )],
      File      => [qw( criteria  criterion )],
      Criterion => [qw( locations location )],
      Location  => [qw( data      datum )],
    };
    my $base = "Devel::Cover::DB::Base";
    while (my ($class, $functions) = each %$classes) {
      my $c = "Devel::Cover::DB::$class";
      no strict "refs";
      @{"${c}::ISA"}             = $base;
      *{"${c}::$functions->[0]"} = \&{"${base}::values"};
      *{"${c}::$functions->[1]"} = \&{"${base}::get"};
    }

    {
      no warnings "once";
      *Devel::Cover::DB::File::DESTROY = sub { };
      unless (exists &Devel::Cover::DB::File::AUTOLOAD) {
        *Devel::Cover::DB::File::AUTOLOAD = sub {
          # Work around a change in bleadperl from 12251 to 14899
          my $func = $Devel::Cover::DB::AUTOLOAD || $::AUTOLOAD;

          (my $f = $func) =~ s/.*:://;
          carp "Undefined subroutine $f called"
            unless any { $_ eq $f } $self->{all_criteria}->@*,
            $self->{all_criteria_short}->@*;
          no strict "refs";
          *$func = sub ($self) { $self->{$f} };
          goto &$func
        };
      }
    }
  }
}

sub _file_digest ($r, $file) {
  my $digest = $r->{digests}{$file};
  return $digest if $digest;
  print STDERR "Devel::Cover: Can't find digest for $file\n"
    unless $Devel::Cover::Silent
    || $file =~ $Devel::Cover::DB::Ignore_filenames
    || ($Devel::Cover::Self_cover && $file =~ "/Devel/Cover[./]");
  undef
}

sub _cover_file (
  $self,  $file,        $f,       $r,     $st,
  $cover, $uncoverable, $digests, $files, $warned,
) {
  my $digest = _file_digest($r, $file) or return;

  print STDERR "Devel::Cover: merging data for $file ",
    "into $digests->{$digest}\n"
    if !$files->{$file}++ && $digests->{$digest};

  $self->uncoverable_comments($uncoverable, $file, $digest)
    unless $digests->{$digest};

  my $ff = $file;
  if ($self->{prefer_lib}) {
    $ff =~ s|^blib/||;
    $ff = $file unless -e $ff;
  }
  my $cf = $cover->{ $digests->{$digest} ||= $ff } ||= {};
  $cf->{meta}{digest} = $digest;

  while (my ($criterion, $fc) = each %$f) {
    my $get = "get_$criterion";
    my $sc  = $st->$get($digest) or do {
      print STDERR "Devel::Cover: Warning: can't locate ",
        "structure for $criterion in $file\n"
        unless $warned->{$file}{$criterion}++;
      next;
    };
    my $cc  = $cf->{$criterion} ||= {};
    my $add = "add_$criterion";
    $self->$add($cc, $sc, $fc, $uncoverable->{$digest}{$criterion});
  }
}

sub cover ($self) {
  return $self->{cover} if $self->{cover_valid};

  my %digests;  # mapping of digests to canonical filenames
  my %files;    # processed files
  my $cover       = $self->{cover} = {};
  my $uncoverable = {};
  require Devel::Cover::DB::Structure;
  my $st = $self->{_structure}
    // Devel::Cover::DB::Structure->new(base => $self->{base})->read_all;

  # Sometimes the start value is undefined.  It's not yet clear why, but it
  # probably has something to do with the code under test forking.  We'll
  # just try to cope with that here.
  my @runs = sort {
    ($self->{runs}{$b}{start} || 0) <=> ($self->{runs}{$a}{start} || 0)
      || $b cmp $a
  } keys $self->{runs}->%*;

  my %warned;
  for my $run (@runs) {
    last unless $st;

    my $r = $self->{runs}{$run};
    next unless $r->{collected};  # DEVEL_COVER_SELF
    $self->{collected}->@{ $r->{collected}->@* } = ();
    $st->add_criteria($r->{collected}->@*);
    my $count = $r->{count};
    while (my ($file, $f) = each %$count) {
      $self->_cover_file(
        $file, $f, $r, $st, $cover,
        $uncoverable, \%digests, \%files, \%warned,
      );
    }
  }

  $self->objectify_cover;
  if ($self->{files}->@*) {
    require Devel::Cover::Static;
    for my $file ($self->{files}->@*) {
      next if exists $self->{cover}{$file};
      my $counts = Devel::Cover::Static::count_criteria($file);
      $self->{cover}{$file}
        = bless {
          meta => { uncompiled => 1, ($counts ? (counts => $counts) : ()) }, },
        "Devel::Cover::DB::File";
    }
  }
  $self->{cover_valid} = 1;
  $self->{cover}
}

sub run_keys ($self) {
  $self->cover unless $self->{cover_valid};
  sort { $self->{runs}{$b}{start} <=> $self->{runs}{$a}{start} }
    keys $self->{runs}->%*
}

sub runs ($self) {
  $self->cover unless $self->{cover_valid};
  $self->{runs}->@{ $self->run_keys }
}

sub set_structure ($self, $structure) {
  $self->{_structure} = $structure;
}

package Devel::Cover::DB::Run;

our $AUTOLOAD;

sub DESTROY { }

sub AUTOLOAD {
  my $func = $AUTOLOAD;
  (my $f = $func) =~ s/.*:://;
  no strict "refs";
  *$func = sub { shift->{$f} };
  goto &$func
}

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::DB - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::DB;

 my $db = Devel::Cover::DB->new(db => "my_coverage_db");
 $db->print_summary([$file1, $file2], ["statement", "pod"]);

=head1 DESCRIPTION

This module provides access to a database of code coverage information.

=head1 METHODS

=head2 new

 my $db = Devel::Cover::DB->new(db => "my_coverage_db");

Constructs the DB from the specified database.

=head2 cover

 my $cover = $db->cover;

Returns a Devel::Cover::DB::Cover object.  From here all the coverage
data may be accessed.

 my $cover = $db->cover;
 for my $file ($cover->items) {
     print "$file\n";
     my $f = $cover->file($file);
     for my $criterion ($f->items) {
         print "  $criterion\n";
         my $c = $f->criterion($criterion);
         for my $location ($c->items) {
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

Aliased to Devel::Cover::DB::Cover->file, Devel::Cover::DB::File->criterion,
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

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

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

  $self->{all_criteria}         = [$self->{criteria}->@*,       "total"];
  $self->{all_criteria_short}   = [$self->{criteria_short}->@*, "total"];
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

sub dir_summary ($self, $dir, $criterion = undef) {
  my $d = $self->{dir_summary}{$dir};
  return $d unless $d && defined $criterion;
  $d->{$criterion}
}

sub slop_sub_lookup ($self, $file) {
  my $slop = $self->summary($file, "slop") or return {};
  my $subs = $slop->{subs}                 or return {};
  +{ map { ("$_->{line}\0$_->{name}" => $_) } @$subs }
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

sub _slop ($crap) {
  $crap > 1 ? log($crap) * 10 : 0
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

sub _file_dir ($file) {
  my $dir = $file =~ s|/[^/]+$||r;
  $dir eq $file ? "" : $dir
}

sub _file_cc_data ($file_obj, $cc_hash, $end_hash) {
  my ($max, $sum, $count) = (0, 0, 0);
  my ($crap_max, $crap_sum) = (0, 0);
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
        push @subs, {
            name => $sub_name,
            line => $line + 0,
            cc   => $cc,
            cov  => $cov,
            crap => $crap,
            slop => _slop($crap),
          };
      }
    }
  }

  return unless $count;
  {
    max      => $max,
    sum      => $sum,
    count    => $count,
    crap_max => $crap_max,
    crap_sum => $crap_sum,
    subs     => \@subs,
  }
}

sub _summarise_dir_complexity ($self, $s, $dir_files, $dir_stats) {
  my $ds_hash = $self->{dir_summary} = {};
  for my $dir (keys %$dir_files) {
    my $d = $ds_hash->{$dir} = {};
    for my $criterion (qw( statement branch condition total )) {
      my ($covered, $total, $error) = (0, 0, 0);
      for my $f ($dir_files->{$dir}->@*) {
        my $c = $s->{$f}{$criterion} or next;
        $covered += $c->{covered} || 0;
        $total   += $c->{total}   || 0;
        $error   += $c->{error}   || 0;
      }
      $d->{$criterion} = {
        covered    => $covered,
        total      => $total,
        error      => $error,
        percentage => $total ? 100 - $error * 100 / $total : 100,
      };
    }

    my $ds = $dir_stats->{$dir};
    if ($ds && $ds->{cc_count}) {
      my $dir_cc   = $ds->{cc_sum} - $ds->{cc_count} + 1;
      my $dir_cov  = _file_coverage($d);
      my $dir_crap = _crap($dir_cc, $dir_cov);
      my $dir_slop = _slop($dir_crap);
      $d->{slop} = {
        file_cc   => $dir_cc,
        file_cov  => $dir_cov,
        file_crap => $dir_crap,
        file_slop => $dir_slop,
      };
    }
  }
}

sub summarise_complexity ($self, $s, $files) {
  my $st = $self->{_structure} or return;
  my ($total_sum, $total_count, $total_max) = (0, 0, 0);
  my ($crap_total_sum, $crap_total_max)     = (0, 0);
  my ($fcrap_total_sum, $fcrap_total_cnt)   = (0, 0);
  my $fslop_total_sum = 0;
  my %dir_stats;
  my %dir_files;

  for my $file (@$files) {
    push $dir_files{ _file_dir($file) }->@*, $file;
  }

  for my $file (@$files) {
    my $file_obj = $self->cover->get($file);
    my $digest   = $file_obj->{meta}{digest};
    next unless $digest;
    my $cc_hash  = $st->get_complexity($digest) or next;
    my $end_hash = $st->get_end_lines($digest) || {};
    my $d        = _file_cc_data($file_obj, $cc_hash, $end_hash) or next;

    my $max   = $d->{max};
    my $sum   = $d->{sum};
    my $count = $d->{count};

    $s->{$file}{complexity}
      = { max => $max, mean => $sum / $count, count => $count };
    my $file_cc   = $sum - $count + 1;
    my $file_cov  = _file_coverage($s->{$file});
    my $file_crap = _crap($file_cc, $file_cov);
    my $file_slop = _slop($file_crap);
    $s->{$file}{slop} = {
      max       => $d->{crap_max},
      mean      => $d->{crap_sum} / $count,
      count     => $count,
      subs      => $d->{subs},
      file_cc   => $file_cc,
      file_cov  => $file_cov,
      file_crap => $file_crap,
      file_slop => $file_slop,
    };
    my $dir = _file_dir($file);
    my $ds  = $dir_stats{$dir} ||= { cc_sum => 0, cc_count => 0 };
    $ds->{cc_sum}   += $sum;
    $ds->{cc_count} += $count;

    $fcrap_total_sum += $file_crap;
    $fslop_total_sum += $file_slop;
    $fcrap_total_cnt++;
    $total_max       = $max if $max > $total_max;
    $total_sum      += $sum;
    $total_count    += $count;
    $crap_total_max  = $d->{crap_max} if $d->{crap_max} > $crap_total_max;
    $crap_total_sum += $d->{crap_sum};
  }
  if ($total_count) {
    $s->{Total}{complexity} = {
      max   => $total_max,
      mean  => $total_sum / $total_count,
      count => $total_count,
    };
  }
  if ($total_count) {
    my $module_cc   = $total_sum - $total_count + 1;
    my $module_cov  = _file_coverage($s->{Total});
    my $module_crap = _crap($module_cc, $module_cov);
    my $module_slop = _slop($module_crap);
    $s->{Total}{slop} = {
      max         => $crap_total_max,
      mean        => $crap_total_sum / $total_count,
      count       => $total_count,
      file_crap   => $fcrap_total_cnt ? $fcrap_total_sum / $fcrap_total_cnt : 0,
      file_slop   => $fcrap_total_cnt ? $fslop_total_sum / $fcrap_total_cnt : 0,
      module_cc   => $module_cc,
      module_cov  => $module_cov,
      module_crap => $module_crap,
      module_slop => $module_slop,
    };
  }

  $self->_summarise_dir_complexity($s, \%dir_files, \%dir_stats);
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
      $cc->{$l}[$n] = [$fc->[$i], $sc->[$i][1]];
    }
    $cc->{$l}[$n][2][$_->[0]] ||= $_->[1] for @{ $uc->{$l}[$n] };
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
      $cc->{$l}[$n] = [$fc->[$i], $sc->[$i][1]];
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
      push $u->{$file}{$crit}{$line}[$count]->@*, [$type, $class, $note];
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
        push @waiting, [$criterion, $c - 1, $type, $class, $note];
      }

      next unless $code =~ /\S/;
    }

    # found what we are waiting for
    while (my $w = shift @waiting) {
      my ($criterion, $count, $type, $class, $note) = @$w;
      push $uncoverable->{$digest}{$criterion}{$.}[$count]->@*,
        [$type, $class, $note];
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
  no warnings "once";
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
  my $st          = $self->{_structure} // do {
    require Devel::Cover::DB::Structure;  ## no perlimports
    Devel::Cover::DB::Structure->new(base => $self->{base})->read_all;
  };

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
          meta => { uncompiled => 1, ($counts ? (counts => $counts) : ()) } },
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

"
You seen the glory and the shame
Beauty and the pain
Weakness and the strength
Waiting for the fame
Don't you think you ought to give it all you got?
"

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

Construct a DB from the specified database directory. If the directory contains
a valid database file it is read automatically.

=head2 criteria

  my @c = $db->criteria;

Return the list of coverage criteria names (e.g. C<statement>, C<branch>,
C<condition>, ...).

=head2 criteria_short

  my @c = $db->criteria_short;

Return the abbreviated criteria names (e.g. C<stmt>, C<bran>, C<cond>, ...).

=head2 all_criteria

  my @c = $db->all_criteria;

Like L</criteria> but includes C<total>.

=head2 all_criteria_short

  my @c = $db->all_criteria_short;

Like L</criteria_short> but includes C<total>.

=head2 files

  my @f = $db->files;

Return the list of extra files registered with the database (e.g. uncompiled
files added via the C<files> option).

=head2 read

  $db->read($file);

Read a serialised database from C<$file>. Populates C<runs> and
C<files>. Returns C<$self>.

=head2 write

  $db->write; $db->write($db_path);

Write the database to disk. If C<$db_path> is given it overrides the current
C<db> attribute. Also writes the structure if one is attached. Returns C<$self>.

=head2 delete

  $db->delete; $db->delete($db_path);

Remove all contents of the database directory. Returns C<$self>.

=head2 clean

  $db->clean;

Remove stale C<.lock> files from the database directory.

=head2 merge_runs

  $db->merge_runs;

Merge individual run files from C<< $db/runs/ >> into the main database, write
the merged result, and delete the run files. Handles changed-file detection: if
a file's digest differs between runs the old coverage is discarded. Returns
C<$self>.

=head2 validate_db

  $db->validate_db;

Warn to STDERR if the database directory looks invalid. Returns C<$self>.

=head2 exists

  my $bool = $db->exists;

Return true if the database directory exists on disk.

=head2 is_valid

  my $valid = $db->is_valid;

Return true if the database is valid (or looks valid - the check is
intentionally lax).

=head2 collected

  my @criteria = $db->collected;

Return the sorted list of criteria that were actually collected during coverage
runs.

=head2 merge

  $db->merge($other_db);

Merge run and collection data from C<$other_db> into C<$self>. Detects changed
files by comparing digests across runs.

=head2 summary

  my $all  = $db->summary($file);
  my $crit = $db->summary($file, "statement");
  my $val  = $db->summary($file, "statement", "percentage");

Access the summary hash for C<$file>. With one argument returns the entire file
summary. With two, the summary for a single criterion. With three, a specific
part of that criterion's summary.

=head2 dir_summary

  my $all  = $db->dir_summary($dir);
  my $crit = $db->dir_summary($dir, "statement");

Access the directory-level summary hash for C<$dir>. Populated by
L</summarise_complexity> during L</calculate_summary>.

=head2 slop_sub_lookup

  my $lookup = $db->slop_sub_lookup($file);

Return a hashref mapping C<"$line\0$name"> to per-subroutine SLOP detail from
the summary data for C<$file>. Returns an empty hashref when no SLOP data
exists.

=head2 summarise_complexity

  $db->summarise_complexity($summary, \@files);

Compute per-file, per-directory, and total complexity and SLOP scores, storing
results into the C<$summary> hash. Called automatically by
L</calculate_summary>.

=head2 calculate_summary

  $db->calculate_summary(statement => 1, branch => 1);

Calculate coverage summaries for all files, filtered by the criteria given as
true-valued keys. Populates C<< $db->{summary} >> and triggers
L</summarise_complexity>.

=head2 trimmed_file

  my $short = Devel::Cover::DB::trimmed_file($filename, $max_len);

Truncate C<$filename> to C<$max_len> characters, replacing the leading portion
with C<...> if necessary. This is a plain function, not a method.

=head2 print_summary

  $db->print_summary; $db->print_summary(\@files, \@criteria, \%opts);

Print a tabular coverage summary to STDOUT. If C<@files> or C<@criteria> are
given they restrict the output.

=head2 add_statement

  $db->add_statement($cc, $sc, $fc, $uc);

Merge statement coverage counts from a single run into the accumulated cover
hash. C<$cc> is the accumulated hash, C<$sc> the structure, C<$fc> the run
counts, and C<$uc> uncoverable data.

=head2 add_time

  $db->add_time($cc, $sc, $fc, $);

Merge time coverage data. Same interface as L</add_statement> but accumulates
into scalar references.

=head2 add_branch

  $db->add_branch($cc, $sc, $fc, $uc);

Merge branch coverage counts. Handles multi-valued branch data (true/false/else
counts).

=head2 add_subroutine

  $db->add_subroutine($cc, $sc, $fc, $uc);

Merge subroutine coverage counts.

=head2 add_condition

Alias for L</add_branch>.

=head2 add_pod

Alias for L</add_subroutine>.

=head2 uncoverable_files

  my @files = $db->uncoverable_files;

Return the list of C<.uncoverable> files to consult, including any specified via
the C<uncoverable_file> option, the local C<.uncoverable>, and
C<~/.uncoverable>.

=head2 uncoverable

  my $uc = $db->uncoverable;

Read all C<.uncoverable> files and return a hashref of uncoverable data keyed by
file digest, criterion, line number, and count.

=head2 add_uncoverable

  $db->add_uncoverable(\@adds);

Append entries to the first uncoverable file.

=head2 delete_uncoverable

  $db->delete_uncoverable(\@deletes);

Remove entries from the uncoverable file. Currently unimplemented.

=head2 clean_uncoverable

  $db->clean_uncoverable;

Clean up the uncoverable file. Currently unimplemented.

=head2 uncoverable_comments

  $db->uncoverable_comments($uncoverable, $file, $digest);

Scan C<$file> for C<# uncoverable> comments and merge them into the
C<$uncoverable> hash under C<$digest>.

=head2 objectify_cover

  $db->objectify_cover;

Bless the raw cover hash into the appropriate C<Devel::Cover::DB::*> classes so
that the OO accessors work.

=head2 cover

  my $cover = $db->cover;

Return a L<Devel::Cover::DB::Cover> object. From here all the coverage data may
be accessed.

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
special handling. This is not yet documented so your best bet for now is to look
at some of the simpler reports and/or the source.

The methods in the above example are actually aliases for methods in
Devel::Cover::DB::Base (the base class for all C<Devel::Cover::DB::*> classes):

=over

=item * Devel::Cover::DB::Base->values

Aliased to Devel::Cover::DB::Cover->files, Devel::Cover::DB::File->criteria,
Devel::Cover::DB::Criterion->locations, and Devel::Cover::DB::Location->data

=item * Devel::Cover::DB::Base->get

Aliased to Devel::Cover::DB::Cover->file, Devel::Cover::DB::File->criterion,
Devel::Cover::DB::Criterion->location, and Devel::Cover::DB::Location->datum

=back

Instead of calling C<< $file->criterion("x") >> you can also call
C<< $file->x >>.

=head2 run_keys

  my @keys = $db->run_keys;

Return run identifiers sorted by start time (most recent first).

=head2 runs

  my @runs = $db->runs;

Return L<Devel::Cover::DB::Run> objects sorted by start time (most recent
first).

=head2 set_structure

  $db->set_structure($struct);

Attach a L<Devel::Cover::DB::Structure> object for use by
L</summarise_complexity>.

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

# Copyright 2004-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::DB::Structure;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Carp        qw( confess croak );
use Digest::MD5 ();
use List::Util  qw( any );

use Devel::Cover::DB     ();
use Devel::Cover::DB::IO ();

# VERSION
our $AUTOLOAD;

sub new ($class, %args) { bless \%args, $class }

sub DESTROY ($self) { }

sub AUTOLOAD {  ## no critic (RequireArgUnpacking) - goto needs @_ intact
  my $self = $_[0];
  my $func = $AUTOLOAD;
  $func =~ s/.*:://;
  my ($function, $criterion) = $func =~ /^(add|get)_(.*)/;
  croak "Undefined subroutine $func called"
    unless $criterion && any { $_ eq $criterion } @Devel::Cover::DB::Criteria,
    qw( sub_name file line );
  no strict "refs";
  if ($function eq "get") {
    my $c = $criterion eq "time" ? "statement" : $criterion;
    if (any { $_ eq $c } qw( sub_name file line )) {
      *$func = sub ($self) { $self->{$c} };
    } else {
      *$func = sub ($self, $digest) {
        for my $fval (values $self->{f}->%*) {
          return $fval->{$c} if $fval->{digest} eq $digest;
        }
        return
      };
    }
  } else {
    *$func = sub ($self, $file, @vals) {
      push $self->{f}{$file}{$criterion}->@*, @vals;
    };
  }
  goto &$func
}

sub add_criteria ($self, @names) {
  $self->{criteria}->@{@names} = ();
  $self
}

sub criteria ($self) { keys $self->{criteria}->%* }

sub reuse ($self, $file) {
  exists $self->{f}{$file}{start}{-1}{__COVER__}
  # TODO - exists $self->{f}{$file}{start}{-1}
}

sub get_count ($self, $file, $criterion) {
  $self->{count}{$criterion}{$file}
}

sub add_count ($self, $criterion) {
  return unless defined $self->{file};  # can happen during self_cover
  $self->{additional_count}{$criterion}{ $self->{file} }++
    if $self->{additional};
  (
    $self->{count}{$criterion}{ $self->{file} }++,
    !$self->reuse($self->{file}) || $self->{additional},
  )
}

sub set_subroutine ($self, $sub_name, $file, $line, $scount) {
  @$self{qw( sub_name file line scount )} = ($sub_name, $file, $line, $scount);

  # When new code is added at runtime, via a string eval in some guise, we need
  # information about where structure information for the subroutine is.  This
  # information is stored in $self->{f}{$file}{start} keyed on the filename,
  # line number, subroutine name and the count, the count being for when there
  # are multiple subroutines of the same name on the same line (such subroutines
  # generally being called BEGIN).

  $self->{additional} = 0;
  if ($self->reuse($file)) {
    # reusing a structure
    if (exists $self->{f}{$file}{start}{$line}{$sub_name}[$scount]) {
      # sub already exists - normal case
      $self->{count}{$_}{$file}
        = $self->{f}{$file}{start}{$line}{$sub_name}[$scount]{$_}
        for $self->criteria;
    } else {
      # sub doesn't exist, for example a conditional C<eval "use M">
      $self->{additional} = 1;
      if (exists $self->{additional_count}{ ($self->criteria)[0] }{$file}) {
        # already had such a sub in module
        $self->{count}{$_}{$file}
          = $self->{f}{$file}{start}{$line}{$sub_name}[$scount]{$_}
          = ($self->add_count($_))[0]
          for $self->criteria;
      } else {
        # first such a sub in module
        $self->{count}{$_}{$file} = $self->{additional_count}{$_}{$file}
          = $self->{f}{$file}{start}{$line}{$sub_name}[$scount]{$_}
          = $self->{f}{$file}{start}{-1}{__COVER__}[$scount]{$_}
          for $self->criteria;
      }
    }
  } else {
    # first time sub seen in new structure
    $self->{count}{$_}{$file}
      = $self->{f}{$file}{start}{$line}{$sub_name}[$scount]{$_}
      = $self->get_count($file, $_)
      for $self->criteria;
  }

  [$file, $line, $sub_name, $scount]
}

sub set_complexity ($self, $sub_id, $cc) {
  my ($file, $line, $sub_name, $scount) = @$sub_id;
  $self->{f}{$file}{complexity}{$line}{$sub_name}[$scount] = $cc;
}

sub _file_by_digest ($self, $digest) {
  if (my $files = $self->{digests}{$digest}) {
    return $self->{f}{ $files->[0] };
  }
  for my $fval (values $self->{f}->%*) {
    return $fval if $fval->{digest} eq $digest;
  }
  return
}

sub get_complexity ($self, $digest) {
  my $fval = $self->_file_by_digest($digest) or return;
  $fval->{complexity}
}

sub set_end_line ($self, $sub_id, $end_line) {
  my ($file, $line, $sub_name, $scount) = @$sub_id;
  $self->{f}{$file}{end_line}{$line}{$sub_name}[$scount] = $end_line;
}

sub get_end_lines ($self, $digest) {
  my $fval = $self->_file_by_digest($digest) or return;
  $fval->{end_line}
}

sub store_counts ($self, $file) {
  $self->{count}{$_}{$file} = $self->{f}{$file}{start}{-1}{__COVER__}[0]{$_}
    = $self->get_count($file, $_)
    for $self->criteria;
}

sub digest ($self, $file) {
  my $digest;
  if (open my $fh, "<", $file) {
    binmode $fh;
    $digest = Digest::MD5->new->addfile($fh)->hexdigest;
  } else {
    print STDERR "Devel::Cover: Warning: can't open $file "
      . "for MD5 digest: $!\n"
      unless lc $file eq "-e"
      or $Devel::Cover::Silent
      or $file =~ $Devel::Cover::DB::Ignore_filenames;
  }
  $digest
}

sub set_file ($self, $file) {
  $self->{file} = $file;
  my $digest = $self->digest($file);
  if ($digest) {
    $self->{f}{$file}{digest} = $digest;
    push $self->{digests}{$digest}->@*, $file;
  }
  $digest
}

sub delete_file ($self, $file) { delete $self->{f}{$file} }

# TODO - concurrent runs updating structure?

sub write ($self, $dir) {
  $dir .= "/structure";
  unless (mkdir $dir) {
    confess "Can't mkdir $dir: $!" unless -d $dir;
  }
  chmod 0777, $dir if $self->{loose_perms};
  for my $file (sort keys $self->{f}->%*) {
    $self->{f}{$file}{file} = $file;
    my $digest = $self->{f}{$file}{digest};
    $digest = $1 if defined $digest && $digest =~ /(.*)/;  # ie tainting
    unless ($digest) {
      print STDERR "Can't find digest for $file"
        unless $Devel::Cover::Silent
        || $file =~ $Devel::Cover::DB::Ignore_filenames
        || ($Devel::Cover::Self_cover && $file =~ "/Devel/Cover[./]");
      next;
    }
    my $df_final = "$dir/$digest";
    my $df_temp  = "$dir/.$digest.$$";
    # TODO - determine if Structure has changed to save writing it
    my $io = Devel::Cover::DB::IO->new;
    $io->write($self->{f}{$file}, $df_temp);               # unless -e $df;
    unless (rename $df_temp, $df_final) {
      unless ($Devel::Cover::Silent) {
        if (-e $df_final) {
          print STDERR "Can't rename $df_temp to $df_final "
            . "(which exists): $!";
        } else {
          print STDERR "Can't rename $df_temp to $df_final: $!";
        }
      }
      unless (unlink $df_temp) {
        print STDERR "Can't remove $df_temp after failed rename: $!"
          unless $Devel::Cover::Silent;
      }
    }
  }
}

sub read ($self, $digest) {
  my $file = "$self->{base}/structure/$digest";
  my $io   = Devel::Cover::DB::IO->new;
  my $s    = eval { $io->read($file) };

  if ($@ || !$s) {
    die $@;
  }
  my $d = $self->digest($s->{file});
  if (!$d) {
    # No digest implies that we can't read the file. Likely this is because it's
    # stored with a relative path. In which case, it's not valid to assume that
    # the file has been changed, and hence that we need to "update" the
    # structure database on disk.
  } elsif ($d eq $s->{digest}) {
    $self->{f}{ $s->{file} } = $s;
    push $self->{digests}{$d}->@*, $s->{file};
  } else {
    print STDERR "Devel::Cover: Deleting old coverage ",
      "for changed file $s->{file}\n"
      unless $Devel::Cover::Silent;
    unless (unlink $file) {
      print STDERR "Devel::Cover: can't delete $file: $!\n"
        unless $Devel::Cover::Silent;
    }
  }
  $self
}

sub read_all ($self) {
  my $dir = $self->{base};
  $dir .= "/structure";
  opendir my $dh, $dir or return;
  for my $d (sort grep !/\./, readdir $dh) {
    $d = $1 if $d =~ /(.*)/;  # De-tainting
    $self->read($d);
  }
  closedir $dh or die "Can't closedir $dir: $!";
  $self
}

sub merge ($self, $from) {
  # TODO - make _merge_hash a public API in Devel::Cover::DB
  Devel::Cover::DB::_merge_hash(  ## no critic (ProtectPrivateSubs)
    $self->{f}, $from->{f}, "noadd",
  )
}

"
So let's shake hands and reach across those party lines
You've got your friends just like I've got mine
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover::DB::Structure - Manage source file structure for coverage data

=head1 SYNOPSIS

 use Devel::Cover::DB::Structure;

 my $struct = Devel::Cover::DB::Structure->new(base => $db_path);
 $struct->add_criteria("statement", "branch");
 my $digest = $struct->set_file($filename);
 $struct->set_subroutine($sub_name, $file, $line, $scount);
 $struct->write($dir);

 # In a later run
 my $struct = Devel::Cover::DB::Structure->new(base => $db_path);
 $struct->read_all;
 $struct->merge($other_struct);

=head1 DESCRIPTION

This module tracks the structural layout of source files being analysed by
L<Devel::Cover>.  It records which subroutines, statements, branches, and
conditions exist in each file, and maps those elements to digest-keyed storage
so that coverage data can be matched to the correct source even across multiple
runs.

Structure information is persisted to the C<structure/> subdirectory of the
coverage database, with one file per source digest.  When a file changes between
runs, the stale structure entry is detected via MD5 digest comparison and
deleted automatically.

=head1 METHODS

=head2 new (%args)

 my $struct = Devel::Cover::DB::Structure->new(base => $path);

Construct a new structure object.  All key-value pairs in C<%args> are stored as
instance attributes.  The C<base> attribute should point to the coverage
database directory.

=head2 add_criteria (@names)

 $struct->add_criteria("statement", "branch", "condition");

Register coverage criteria that this structure should track.  Returns C<$self>.

=head2 criteria

 my @names = $struct->criteria;

Return the list of registered criteria names.

=head2 reuse ($file)

 my $bool = $struct->reuse($file);

Return true if C<$file> already has stored structure information from a previous
run that can be reused.

=head2 get_count ($file, $criterion)

 my $count = $struct->get_count($file, $criterion);

Return the current counter value for C<$criterion> in C<$file>.

=head2 add_count ($criterion)

 my ($count, $is_new) = $struct->add_count($criterion);

Increment and return the counter for C<$criterion> in the current file. The
second return value is true when the count represents a new (not reused)
structure entry.

=head2 set_subroutine ($sub_name, $file, $line, $scount)

Record the start of subroutine C<$sub_name> at C<$file>:C<$line>. C<$scount>
disambiguates multiple subroutines with the same name on the same line
(typically C<BEGIN> blocks).

Handles three cases: reusing existing structure, adding a new subroutine to a
reused structure (e.g. a conditional C<< eval "use M" >>), and recording a
subroutine in a new structure.

Returns a sub_id arrayref C<[$file, $line, $sub_name, $scount]> suitable for
passing to L</set_complexity>.

=head2 set_complexity ($sub_id, $cc)

 $struct->set_complexity($sub_id, 5);

Store cyclomatic complexity C<$cc> for a subroutine identified by C<$sub_id>
(as returned by L</set_subroutine>).  The value is stored at
C<< $self-E<gt>{f}{$file}{complexity}{$line}{$sub_name}[$scount] >>.

=head2 get_complexity ($digest)

 my $complexity = $struct->get_complexity($digest);

Return the complexity hash for the file matching C<$digest>, or C<undef> if no
file matches.  The returned hash is keyed by line number, then subroutine name,
with an arrayref of CC values indexed by C<$scount>.

=head2 store_counts ($file)

Initialise counter storage for C<$file> across all registered criteria.

=head2 digest ($file)

 my $hex = $struct->digest($file);

Return the MD5 hex digest of C<$file>, or C<undef> if the file cannot be opened.

=head2 set_file ($file)

 my $digest = $struct->set_file($file);

Record C<$file> as the current file, compute its digest, and register the
file-to-digest mapping.  Returns the digest.

=head2 delete_file ($file)

Remove all structure information for C<$file>.

=head2 write ($dir)

Serialise each file's structure to C<< $dir/structure/<digest> >>. Uses atomic
rename to avoid partial writes.

=head2 read ($digest)

 $struct->read($digest);

Load structure for C<$digest> from disk.  If the source file has changed since
the structure was written, the stale entry is deleted. Returns C<$self>.

=head2 read_all

 $struct->read_all;

Load all structure files from the database directory.  Returns C<$self>.

=head2 merge ($from)

 $struct->merge($other_struct);

Merge structure information from C<$from> into this object.

=head1 AUTOLOADED METHODS

Methods of the form C<< add_<criterion> >> and C<< get_<criterion> >> are
generated on first call via C<AUTOLOAD> for each coverage criterion
(e.g. C<add_statement>, C<get_branch>), as well as for the meta-fields
C<sub_name>, C<file>, and C<line>.

=head1 SEE ALSO

L<Devel::Cover>, L<Devel::Cover::DB>

=head1 LICENCE

Copyright 2004-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

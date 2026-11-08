# Copyright 2011-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::DB::Digests;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use File::Spec ();

use Devel::Cover::DB::IO ();
use Devel::Cover::Log    qw( dcinfo dcwarn );

my $File = "digests";

sub new ($class, @args) {
  my $self = { digests => {}, @args };

  die "No db specified" unless $self->{db};
  $self->{file} = "$self->{db}/$File";

  bless $self, $class;
  $self->read;
  $self
}

sub read ($self) {
  my $io = Devel::Cover::DB::IO->new(loose_perms => $self->{loose_perms});
  if (-e $self->{file}) {
    # The file is only a cache, so never die because of it
    my $digests = eval { $io->read($self->{file}) };
    if ($@ || !$digests) {
      chomp(my $err = $@ || "no data");
      dcwarn "Ignoring unreadable digests file $self->{file}: $err";
      $digests = {};
    }
    $self->{digests} = $digests;
  }
  $self
}

sub write ($self) {
  my $io = Devel::Cover::DB::IO->new(loose_perms => $self->{loose_perms});
  $io->write($self->{digests}, $self->{file});
  $self
}

sub get ($self, $digest) {
  $self->{digests}{$digest}
}

sub set ($self, $file, $digest) {
  $self->{digests}{$digest} = $file;
}

sub _holds ($self, $file, $digest) {
  my $path = File::Spec->rel2abs($file, $self->{dir});
  return unless -e $path;
  my $found = Devel::Cover::DB::Structure->digest($path);
  $found && $found eq $digest
}

sub canonical_file ($self, $file) {
  my $cfile = $file;
  require Devel::Cover::DB::Structure;
  my $digest = Devel::Cover::DB::Structure->digest($file);

  if ($digest) {
    my $dfile = $self->get($digest);
    if ($dfile && $dfile ne $file && $self->_holds($dfile, $digest)) {
      dcinfo "Adding coverage for $file to $dfile";
      $cfile = $dfile;
    } else {
      $self->set($file, $digest);
    }
  }

  # warn "[$file] => [$cfile]\n";

  $cfile
}

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::DB::Digests - store digests for Devel::Cover::DB

=head1 SYNOPSIS

 use Devel::Cover::DB::Digests;
 my $digests = Devel::Cover::DB::Digests->new(db => $DB);
 $digests->read;
 $digests->write;

=head1 DESCRIPTION

This module stores digests for Devel::Cover::DB.

=head1 SEE ALSO

 Devel::Cover
 Devel::Cover::DB

=head1 METHODS

=head2 new

 my $digests = Devel::Cover::DB::Digests->new(db => $DB, dir => $Dir);

Constructs the digests object.  C<dir> is the directory that relative file
names are relative to.  It defaults to the current directory.

=head2 read

 $digests->read;

Read the digests from the DB.

=head2 write

 $digests->write;

Write the digests to the DB.

=head2 canonical_file ($file)

 my $name = $digests->canonical_file($file);

Return the name under which to record coverage for C<$file>.  If the digests
map the content of C<$file> to another name, and that name still holds the
same content, return that name.  Otherwise store C<$file> against its digest
and return C<$file>.

=head1 LICENCE

Copyright 2011-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
L<https://pjcj.net>

=cut

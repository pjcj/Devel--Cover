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

use Devel::Cover::DB::IO;
use Devel::Cover::Log qw( dcinfo dcwarn );

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
  my $io = Devel::Cover::DB::IO->new;
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
  my $io = Devel::Cover::DB::IO->new;
  $io->write($self->{digests}, $self->{file});
  $self
}

sub get ($self, $digest) {
  $self->{digests}{$digest}
}

sub set ($self, $file, $digest) {
  $self->{digests}{$digest} = $file;
}

sub canonical_file ($self, $file) {
  my $cfile = $file;
  require Devel::Cover::DB::Structure;
  my $digest = Devel::Cover::DB::Structure->digest($file);

  if ($digest) {
    my $dfile = $self->get($digest);
    if ($dfile && $dfile ne $file) {
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

 my $digests = Devel::Cover::DB::Digests->new(db => $DB);

Constructs the digests object.

=head2 read

 $digests->read;

Read the digests from the DB.

=head2 write

 $digests->write;

Write the digests to the DB.

=head1 LICENCE

Copyright 2011-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

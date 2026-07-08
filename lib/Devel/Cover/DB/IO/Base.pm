# Copyright 2017-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::DB::IO::Base;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Fcntl qw( LOCK_EX LOCK_SH );

# VERSION

sub new ($class, @args) {
  bless {@args}, $class
}

sub _lock ($self, $file, $type) {
  my $lock = "$file.lock";
  open my $fh, "+>>", $lock or die "Can't open $lock: $!\n";
  flock $fh, $type or die "Can't lock $lock: $!\n";
  $fh
}

sub _read ($self, $file, $reader) {
  my $lock_fh = $self->_lock($file, LOCK_SH);
  $reader->()
}

sub _write ($self, $file, $writer) {
  my $lock_fh = $self->_lock($file, LOCK_EX);
  unlink $file;
  $writer->();
  $self
}

sub read_fh ($self, $file, $reader) {
  $self->_read(
    $file,
    sub {
      open my $fh, "<", $file or die "Can't open $file: $!\n";
      my $data = $reader->($fh);
      close $fh or die "Can't close $file: $!\n";
      $data
    },
  )
}

sub write_fh ($self, $file, $writer) {
  $self->_write(
    $file,
    sub {
      open my $fh, ">", $file or die "Can't open $file: $!\n";
      $writer->($fh);
      close $fh or die "Can't close $file: $!\n";
    },
  )
}

"
Green trees call to me
I am free but life is so cheap
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover::DB::IO::Base - Base class for IO routines for Devel::Cover::DB

=head1 SYNOPSIS

 use parent "Devel::Cover::DB::IO::Base";

=head1 DESCRIPTION

This module is a base class for IO routines for Devel::Cover::DB.

=head1 SEE ALSO

L<Devel::Cover>

=head1 METHODS

=head2 read_fh ($file, $reader)

Call C<$reader> with a filehandle open for reading C<$file>, holding a shared
lock, and return its result.

=head2 write_fh ($file, $writer)

Call C<$writer> with a filehandle to write the data for C<$file>, holding an
exclusive lock.

=head1 LICENCE

Copyright 2017-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

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
  # another user may own the lock and have set the mode already
  chmod 0666, $lock if $self->{loose_perms};
  flock $fh, $type or die "Can't lock $lock: $!\n";
  $fh
}

sub _close_after ($fh, $what, $code) {
  my $data = eval { $code->() };
  my $err  = $@;
  $err ||= "Can't close $what: $!\n" unless close $fh;
  die $err if $err;
  $data
}

sub _read ($self, $file, $reader) {
  _close_after($self->_lock($file, LOCK_SH), "$file.lock", $reader)
}

sub _write ($self, $file, $writer) {
  my $lock_fh = $self->_lock($file, LOCK_EX);
  my $tmp     = "$file.tmp.$$";
  _close_after(
    $lock_fh,
    "$file.lock",
    sub {
      eval { $writer->($tmp); 1 } or do { my $e = $@; unlink $tmp; die $e };
      rename $tmp, $file or do {
        unlink $tmp;
        die "Can't rename $tmp to $file: $!\n";
      };
    },
  );
  $self
}

sub read_fh ($self, $file, $reader) {
  $self->_read(
    $file,
    sub {
      open my $fh, "<", $file or die "Can't open $file: $!\n";
      _close_after($fh, $file, sub { $reader->($fh) })
    },
  )
}

sub write_fh ($self, $file, $writer) {
  $self->_write(
    $file,
    sub ($tmp) {
      open my $fh, ">", $tmp or die "Can't open $tmp: $!\n";
      _close_after($fh, $tmp, sub { $writer->($fh) })
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

=head1 PRIVATE SUBROUTINES

=head2 _lock ($self, $file, $type)

Open F<$file.lock>, creating it if necessary, take a C<flock> of C<$type> on it
and return the handle. With C<loose_perms> set, make the lock file world
writable so that another user can take the lock later.

=head2 _close_after ($fh, $what, $code)

Call C<$code> in scalar context, close C<$fh> whether C<$code> returned or
died, and return the result. An error from C<$code> is rethrown after the close
and takes precedence over a close failure, whose message names C<$what>. Every
reader and writer returns a single value, so the scalar context loses nothing.

=head2 _read ($self, $file, $reader)

Call C<$reader> under a shared lock on C<$file> and return its result.

=head2 _write ($self, $file, $writer)

Call C<$writer> with a temporary file name under an exclusive lock on
C<$file>, then rename the temporary file into place so that readers see either
the old data or the new. Remove the temporary file if the writer or the rename
fails.

=head1 LICENCE

Copyright 2017-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

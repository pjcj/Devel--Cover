# Copyright 2017-2024, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB::IO::Base;

use strict;
use warnings;

use Fcntl ":flock";

# VERSION

sub new {
  my $class = shift;
  bless {@_}, $class
}

sub _lock {
  my $self = shift;
  my ($file, $type) = @_;
  my $lock = "$file.lock";
  open my $fh, "+>>", $lock or die "Can't open $lock: $!\n";
  flock $fh, $type or die "Can't lock $lock: $!\n";
  $fh
}

sub _read {
  my $self = shift;
  my ($file, $reader) = @_;
  my $lock_fh = $self->_lock($file, LOCK_SH);
  $reader->()
}

sub _write {
  my $self = shift;
  my ($file, $writer) = @_;
  my $lock_fh = $self->_lock($file, LOCK_EX);
  unlink $file;
  $writer->();
  $self
}

sub _read_fh {
  my $self = shift;
  my ($file, $reader) = @_;
  $self->_read(
    $file,
    sub {
      open my $fh, "<", $file or die "Can't open $file: $!\n";
      my $data = $reader->($fh);
      close $fh or die "Can't close $file: $!\n";
      $data
    }
  )
}

sub _write_fh {
  my $self = shift;
  my ($file, $writer) = @_;
  $self->_write(
    $file,
    sub {
      open my $fh, ">", $file or die "Can't open $file: $!\n";
      $writer->($fh);
      close $fh or die "Can't close $file: $!\n";
    }
  )
}

"
Green trees call to me
I am free but life is so cheap
"

__END__

=head1 NAME

Devel::Cover::DB::IO::Base - Base class for IO routines for Devel::Cover::DB

=head1 SYNOPSIS

 use parent "Devel::Cover::DB::IO::Base";

=head1 DESCRIPTION

This module is a base class for IO routines for Devel::Cover::DB.

=head1 SEE ALSO

L<Devel::Cover>

=head1 METHODS

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2017-2024, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

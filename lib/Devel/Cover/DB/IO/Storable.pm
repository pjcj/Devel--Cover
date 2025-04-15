# Copyright 2011-2025, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB::IO::Storable;

use strict;
use warnings;

use base "Devel::Cover::DB::IO::Base";

use Storable;

# VERSION

sub new {
  my $class = shift;
  my $self  = $class->SUPER::new(@_);
  bless $self, $class
}

sub read {
  my $self = shift;
  my ($file) = @_;
  $self->_read($file, sub { Storable::retrieve($file) })
}

sub write {
  my $self = shift;
  my ($data, $file) = @_;
  $self->_write($file, sub { Storable::nstore($data, $file) })
}

1

__END__

=head1 NAME

Devel::Cover::DB::IO::Storable - Storable based IO routines for Devel::Cover::DB

=head1 SYNOPSIS

 use Devel::Cover::DB::IO::Storable;

 my $io = Devel::Cover::DB::IO::Storable->new;
 my $data = $io->read($file);
 $io->write($data, $file);

=head1 DESCRIPTION

This module provides Storable based IO routines for Devel::Cover::DB.

=head1 SEE ALSO

 Devel::Cover

=head1 METHODS

=head2 new

 my $io = Devel::Cover::DB::IO::Storable->new;

Constructs the IO object.

=head2 read

 my $data = $io->read($file);

Returns a perl data structure representing the data read from $file.

=head2 write

 $io->write($data, $file);

Writes $data to $file in the format specified when creating $io.

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2011-2025, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

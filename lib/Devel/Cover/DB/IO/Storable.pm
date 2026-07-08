# Copyright 2011-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::DB::IO::Storable;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use base "Devel::Cover::DB::IO::Base";

use Storable ();

# VERSION

sub new ($class, @args) {
  my $self = $class->SUPER::new(@args);
  bless $self, $class
}

sub read ($self, $file) {
  $self->read_fh(
    $file,
    sub ($fh) {
      binmode $fh;
      Storable::fd_retrieve($fh)
    },
  )
}

sub write ($self, $data, $file) {
  $self->write_fh(
    $file,
    sub ($fh) {
      binmode $fh;
      Storable::nstore_fd($data, $fh);
    },
  )
}

"
Oh I, I believe in magic and I believe in dreams
Until I heard the thunder rumble
I saw the mountains crumble
Then came the circus, so I followed its parade
"

__END__

=encoding utf8

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

=head1 LICENCE

Copyright 2011-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

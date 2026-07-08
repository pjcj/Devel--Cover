# Copyright 2014-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::DB::IO::Sereal;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use base "Devel::Cover::DB::IO::Base";

use Sereal::Decoder ();
use Sereal::Encoder ();

# VERSION

my ($Decoder, $Encoder);

sub new ($class, @args) {
  my $self = $class->SUPER::new(@args);
  bless $self, $class
}

sub read ($self, $file) {
  $self->read_fh(
    $file,
    sub ($fh) {
      local $/;
      my $data
        = eval { ($Decoder ||= Sereal::Decoder->new({}))->decode(<$fh>) };
      die "Can't read $file with Sereal: $@" if $@;
      $data
    },
  )
}

sub write ($self, $data, $file) {
  $self->write_fh(
    $file,
    sub ($fh) {
      print $fh ($Encoder ||= Sereal::Encoder->new({}))->encode($data);
    },
  )
}

"
Norman and Norma had three lovely daughters
Nadia, Nora and Neive
The firm Norma worked at wouldn't take her back
After maternity leave
They dreamt of Majorca, but couldn't afford to go
On Norman's salary
So they went to Cromer, got double pneumonia
And Norma remembered when she used to say
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover::DB::IO::Sereal - Sereal based IO routines for Devel::Cover::DB

=head1 SYNOPSIS

 use Devel::Cover::DB::IO::Sereal;

 my $io = Devel::Cover::DB::IO::Sereal->new;
 my $data = $io->read($file);
 $io->write($data, $file);

=head1 DESCRIPTION

This module provides Sereal based IO routines for Devel::Cover::DB.

=head1 SEE ALSO

 Devel::Cover

=head1 METHODS

=head2 new

 my $io = Devel::Cover::DB::IO::Sereal->new;

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

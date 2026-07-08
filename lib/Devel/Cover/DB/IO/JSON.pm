# Copyright 2011-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::DB::IO::JSON;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use base "Devel::Cover::DB::IO::Base";

use JSON::MaybeXS ();

# VERSION

sub new ($class, %args) {
  my $json = JSON::MaybeXS->new(utf8 => 1, allow_blessed => 1);
  $json->ascii->pretty->canonical
    if exists $args{options} && $args{options} =~ /\bpretty\b/i;
  my $self = $class->SUPER::new(%args, json => $json);
  bless $self, $class
}

sub read ($self, $file) {
  $self->read_fh(
    $file,
    sub ($fh) {
      local $/;
      my $data = eval { $self->{json}->decode(<$fh>) };
      die "Can't read $file with ", (ref $self->{json}), ": $@" if $@;
      $data
    },
  )
}

sub write ($self, $data, $file) {
  $self->write_fh(
    $file,
    sub ($fh) {
      print $fh $self->{json}->encode($data);
    },
  )
}

"
Oh, and that's all I heard about Brenda and Eddie
Can't tell you more 'cause I told you already
And here we are waving Brenda and Eddie goodbye
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover::DB::IO::JSON - JSON based IO routines for Devel::Cover::DB

=head1 SYNOPSIS

 use Devel::Cover::DB::IO::JSON;

 my $io = Devel::Cover::DB::IO::JSON->new;
 my $data = $io->read($file);
 $io->write($data, $file);

=head1 DESCRIPTION

This module provides JSON based IO routines for Devel::Cover::DB.

=head1 SEE ALSO

L<Devel::Cover>
L<JSON::MaybeXS>

=head1 METHODS

=head2 new

 my $io = Devel::Cover::DB::IO::JSON->new;

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

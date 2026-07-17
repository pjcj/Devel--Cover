# Copyright 2011-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::DB::IO;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

my $Format;

BEGIN {
  $Format = "Sereal"   if eval "use Sereal::Decoder; use Sereal::Encoder; 1";
  $Format = "JSON"     if !$Format && eval { require JSON::MaybeXS; 1 };
  $Format = "Storable" if !$Format && eval "use Storable; 1";
  die "Can't load either JSON or Storable" unless $Format;
}

my %Backend;

sub _backend ($format) {
  $Backend{$format} //= do {
    my $class = "Devel::Cover::DB::IO::$format";
    eval "use $class; 1"
      or die "Devel::Cover: the database needs the $format backend: $@";
    $class
  }
}

sub new ($class, %args) {
  $args{options} //= $ENV{DEVEL_COVER_IO_OPTIONS} || "";

  my $arg_format = delete $args{format};
  my $format     = $ENV{DEVEL_COVER_DB_FORMAT} || $arg_format || $Format;
  ($format) = $format =~ /(.*)/;  # die tainting
  die "Devel::Cover: Unrecognised DB format: $format"
    unless $format =~ /^(?:Storable|JSON|Sereal)$/;

  bless { format => $format, args => \%args }, $class
}

sub _sniff_format ($file) {
  open my $fh, "<", $file or return undef;
  binmode $fh;
  read $fh, my $magic, 4;
  close $fh or return undef;
  return undef unless defined $magic;
  return "Sereal"   if $magic =~ /^=(?:srl|\xF3rl)/;
  return "Storable" if $magic =~ /^pst0/;
  return "JSON"     if $magic =~ /^\s*[\[{]/;
  undef
}

sub read ($self, $file) {
  my $format = _sniff_format($file) // $self->{format};
  _backend($format)->new($self->{args}->%*)->read($file)
}

sub write ($self, $data, $file) {
  _backend($self->{format})->new($self->{args}->%*)->write($data, $file)
}

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::DB::IO - IO routines for Devel::Cover::DB

=head1 SYNOPSIS

 use Devel::Cover::DB::IO;

 my $io = Devel::Cover::DB::IO->new(format => "JSON");
 my $data = $io->read($file);
 $io->write($data, $file);

=head1 DESCRIPTION

This module provides IO routines for Devel::Cover::DB.

=head1 SEE ALSO

 Devel::Cover

=head1 METHODS

=head2 new

 my $io = Devel::Cover::DB::IO->new(format => "JSON");

Constructs the IO object.  The write format is taken from the
C<DEVEL_COVER_DB_FORMAT> environment variable if set, then from the C<format>
argument, then from whichever backend is available (Sereal, JSON, Storable,
in that order).

=head2 read

 my $data = $io->read($file);

Returns a perl data structure representing the data read from $file.  The
format of the file on disk is detected from its content, so a database
written under a different configuration can still be read.

=head2 write

 $io->write($data, $file);

Writes $data to $file in the format specified when creating $io.

=head1 LICENCE

Copyright 2011-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

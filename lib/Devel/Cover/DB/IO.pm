# Copyright 2011-2013, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB::IO;

use strict;
use warnings;

# VERSION

my $Format;

BEGIN
{
    $Format = "JSON"     if              eval "use JSON; 1";
    $Format = "JSON"     if !$Format and eval "use JSON::PP; 1";
    $Format = "Storable" if !$Format and eval "use Storable; 1";
    die "Can't load either JSON or Storable" unless $Format;
}

sub new
{
    my $class = shift;

    my $format = $ENV{DEVEL_COVER_DB_FORMAT} || $Format;
    die "Devel::Cover: Unrecognised DB format: $format"
        unless $format =~ /^(?:Storable|JSON)$/;

    $class .= "::$format";
    eval "use $class; 1" or die "Devel::Cover: $@";

    $class->new(options => $ENV{DEVEL_COVER_IO_OPTIONS} || "", @_)
}

1

__END__

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

Contructs the IO object.

=head2 read

 my $data = $io->read($file);

Returns a perl data structure representing the data read from $file.

=head2 write

 $io->write($data, $file);

Writes $data to $file in the format specified when creating $io.

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2011-2013, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

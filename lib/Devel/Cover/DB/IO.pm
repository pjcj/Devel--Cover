# Copyright 2011, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB::IO;

use strict;
use warnings;

our $VERSION = "0.74";

my $Format;

BEGIN
{
    $Format = eval { require JSON::PP; 1 } ? "JSON" : "Storable";
}

sub new
{
    my $class = shift;
    my $self  =
    {
        format => $Format,
        @_
    };

    if ($self->{format} eq "Storable")
    {
        require Storable;
    }
    elsif ($self->{format} eq "JSON")
    {
        require JSON::PP;
    }
    else
    {
        die "Devel::Cover: Unrecognised DB format: $self->{format}";
    }

    bless $self, $class
}

sub read
{
    my $self   = shift;
    my ($file) = @_;

    if ($self->{format} eq "Storable")
    {
        return Storable::retrieve($file);
    }

    open my $fh, "<", $file or die "Can't open $file: $!";
    local $/;
    my $data = JSON::PP::decode_json(<$fh>);
    close $fh or die "Can't close $file: $!";
    $data
}

sub write
{
    my $self = shift;
    my ($data, $file) = @_;

    if ($self->{format} eq "Storable")
    {
        return Storable::nstore($data, $file);
    }

    open my $fh, ">", $file or die "Can't open $file: $!";
    print $fh "", JSON::PP::encode_json($data);  # "", for 5.6.1
    close $fh or die "Can't close $file: $!";
    $self
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

Returns a perl data structure representingthe data read from $file.

=head2 write

 $io->write($data, $file);

Writes $data to $file in the format specified when creating $io.

=head1 BUGS

Huh?

=head1 VERSION

Version 0.74 - 16th April 2011

=head1 LICENCE

Copyright 2001-2011, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

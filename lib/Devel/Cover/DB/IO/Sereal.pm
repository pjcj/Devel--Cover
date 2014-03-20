# Copyright 2014, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB::IO::Sereal;

use strict;
use warnings;

use Fcntl ":flock";
use Sereal::Decoder;
use Sereal::Encoder;

# VERSION

my $Decoder;
my $Encoder;

sub new
{
    my $class = shift;
    my $self  = { @_ };
    bless $self, $class
}

sub read
{
    my $self   = shift;
    my ($file) = @_;

    open my $fh, "<", $file or die "Can't open $file: $!\n";
    flock $fh, LOCK_SH      or die "Can't lock $file: $!\n";
    local $/;
    my $data;
    eval {
        $Decoder ||= Sereal::Decoder->new({});
        $data = $Decoder->decode(<$fh>);
    };
    die "Can't read $file with Sereal $@" if $@;
    close $fh or die "Can't close $file: $!\n";
    $data
}

sub write
{
    my $self = shift;
    my ($data, $file) = @_;

    $Encoder ||= Sereal::Encoder->new({});
    open my $fh, ">", $file or die "Can't open $file: $!\n";
    flock $fh, LOCK_EX      or die "Can't lock $file: $!\n";
    print $fh $Encoder->encode($data);
    close $fh or die "Can't close $file: $!\n";
    $self
}

1

__END__

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

Copyright 2011-2014, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

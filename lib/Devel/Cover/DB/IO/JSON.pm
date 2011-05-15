# Copyright 2011, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB::IO::JSON;

use strict;
use warnings;

use Fcntl ":flock";
use JSON::PP;

our $VERSION = "0.77";

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

    open my $fh, "<", $file or die "Can't open $file: $!";
    flock($fh, LOCK_SH) or die "Cannot lock file: $!\n";
    local $/;
    my $data = JSON::PP::decode_json(<$fh>);
    close $fh or die "Can't close $file: $!";
    $data
}

sub write
{
    my $self = shift;
    my ($data, $file) = @_;

    my $json = JSON::PP->new->utf8;
    $json->ascii->pretty->canonical if $self->{options} =~ /\bpretty\b/i;
    open my $fh, ">", $file or die "Can't open $file: $!";
    flock($fh, LOCK_EX) or die "Cannot lock file: $!\n";
    print $fh $json->encode($data);
    close $fh or die "Can't close $file: $!";
    $self
}

1

__END__

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

 Devel::Cover

=head1 METHODS

=head2 new

 my $io = Devel::Cover::DB::IO::JSON->new;

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

Version 0.77 - 15th May 2011

=head1 LICENCE

Copyright 2001-2011, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

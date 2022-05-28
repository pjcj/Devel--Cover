# Copyright 2011-2022, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB::IO::JSON;

use strict;
use warnings;

use base "Devel::Cover::DB::IO::Base";

use JSON::MaybeXS ();

# VERSION

sub new {
    my $class = shift;
    my %args = @_;
    my $json = JSON::MaybeXS->new(utf8 => 1, allow_blessed => 1);
    $json->ascii->pretty->canonical
        if exists $args{options} && $args{options} =~ /\bpretty\b/i;
    my $self = $class->SUPER::new(%args, json => $json);
    bless $self, $class
}

sub read {
    my $self   = shift;
    my ($file) = @_;
    $self->_read_fh($file, sub {
        my ($fh) = @_;
        local $/;
        my $data = eval { $self->{json}->decode(<$fh>) };
        die "Can't read $file with ", (ref $self->{json}), ": $@" if $@;
        $data
    })
}

sub write {
    my $self = shift;
    my ($data, $file) = @_;
    $self->_write_fh($file, sub {
        my ($fh) = @_;
        print $fh $self->{json}->encode($data);
    })
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

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2011-2022, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

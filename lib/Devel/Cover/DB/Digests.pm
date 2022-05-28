# Copyright 2011-2022, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB::Digests;

use strict;
use warnings;

# VERSION

use Devel::Cover::DB::Structure;
use Devel::Cover::DB::IO;

my $File = "digests";

sub new {
    my $class = shift;
    my $self  = {
        digests => {},
        @_
    };

    die "No db specified" unless $self->{db};
    $self->{file} = "$self->{db}/$File";

    bless $self, $class;
    $self->read;
    $self
}

sub read {
    my $self = shift;
    my $io = Devel::Cover::DB::IO->new;
    $self->{digests} = $io->read($self->{file}) if -e $self->{file};
    $self
}

sub write {
    my $self = shift;
    my $io = Devel::Cover::DB::IO->new;
    $io->write($self->{digests}, $self->{file});
    $self
}

sub get {
    my $self = shift;
    my ($digest) = @_;
    $self->{digests}{$digest}
}

sub set {
    my $self = shift;
    my ($file, $digest) = @_;
    $self->{digests}{$digest} = $file;
}

sub canonical_file {
    my $self = shift;
    my ($file) = @_;

    my $cfile = $file;
    my $digest = Devel::Cover::DB::Structure->digest($file);
    if ($digest) {
        my $dfile = $self->get($digest);
        if ($dfile && $dfile ne $file) {
            print STDERR "Devel::Cover: Adding coverage for $file to $dfile\n"
                unless $Devel::Cover::Silent;
            $cfile = $dfile;
        } else {
            $self->set($file, $digest);
        }
    }

    # warn "[$file] => [$cfile]\n";

    $cfile
}

1

__END__

=head1 NAME

Devel::Cover::DB::Digests - store digests for Devel::Cover::DB

=head1 SYNOPSIS

 use Devel::Cover::DB::Digests;
 my $digests = Devel::Cover::DB::Digests->new(db => $DB);
 $digests->read;
 $digests->write;

=head1 DESCRIPTION

This module stores digests for Devel::Cover::DB.

=head1 SEE ALSO

 Devel::Cover
 Devel::Cover::DB

=head1 METHODS

=head2 new

 my $digests = Devel::Cover::DB::Digests->new(db => $DB);

Constructs the digests object.

=head2 read

 $digests->read;

Read the digests from the DB.

=head2 write

 $digests->write;

Write the digests to the DB.

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2011-2022, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

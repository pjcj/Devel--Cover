# Copyright 2004, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB::Structure;

use strict;
use warnings;

use Carp;
use Digest::MD5;
use Storable;

our $VERSION = "0.45";
our $AUTOLOAD;

sub new
{
    my $class = shift;
    my $self  = { @_ };

    bless $self, $class;

    $self->read if $self->{base} && $self->{digest};

    $self
}

sub DESTROY {}

sub AUTOLOAD
{
    my $func = $AUTOLOAD;
    $func =~ s/.*:://;
    my ($function, $criterion) = $func =~ /^(add|get)_(.*)/;
    require Devel::Cover::DB;
    croak "Undefined subroutine $func called"
        unless $criterion &&
               grep $_ eq $criterion, Devel::Cover::DB->new->criteria;
    no strict "refs";
    if ($function eq "get")
    {
        my $c = $criterion eq "time" ? "statement" : $criterion;
        *$func = sub
        {
            my $self = shift;
            $self->{$c}
        };
    }
    else
    {
        *$func = sub
        {
            my $self = shift;
            my $file = shift;
            push @{$self->{$file}{$criterion}}, @_;
        };
    }
    goto &$func
}

sub add_digest
{
    my $self = shift;
    my ($file, $run) = @_;
    if (open my $fh, "<", $file)
    {
        binmode $fh;
        $run->{digest}{$file} = Digest::MD5->new->addfile($fh)->hexdigest;
        $self->set_digest($file, $run->{digest}{$file});
    }
    else
    {
        warn "Devel::Cover: Can't open $file for MD5 digest: $!\n";
        # warn "in ", `pwd`;
    }
}

sub set_digest
{
    my $self = shift;
    my ($file, $digest) = @_;
    $self->{$file}{digest} = $digest;
}

sub delete_file
{
    my $self = shift;
    my ($file) = @_;
    delete $self->{$file};
}

sub write
{
    my $self = shift;
    my ($dir) = @_;
    $dir .= "/structure";
    unless (-d $dir)
    {
        mkdir $dir, 0777 or croak "Cannot mkdir $dir: $!\n";
    }
    for my $file (sort keys %$self)
    {
        $self->{$file}{file} = $file;  # just for debugging
        unless ($self->{$file}{digest})
        {
            warn "Can't find digest for $file";
            next;
        }
        my $df = "$dir/$self->{$file}{digest}";
       # my $f = $df; my $n = 1; $df = $f . "." . $n++ while -e $df;
        Storable::nstore($self->{$file}, $df) unless -e $df;
    }
}

sub read
{
    my ($self) = @_;
    my $file   = "$self->{base}/structure/$self->{digest}";
    my $s      = retrieve($file);
    $_[0] = bless $s, ref $self
}

1

__END__

=head1 NAME

Devel::Cover::DB::Structure - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::DB::Structure;

=head1 DESCRIPTION

=head1 SEE ALSO

 Devel::Cover

=head1 METHODS

=head1 BUGS

Huh?

=head1 VERSION

Version 0.45 - 27th May 2004

=head1 LICENCE

Copyright 2001-2004, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

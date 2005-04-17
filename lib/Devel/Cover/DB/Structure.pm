# Copyright 2004-2005, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB::Structure;

use strict;
use warnings;

use Carp;
use Digest::MD5;
use Storable;

use Devel::Cover::DB;

our $VERSION = "0.53";
our $AUTOLOAD;

sub new
{
    my $class = shift;
    my $self  =
    {
        @_
    };
    bless $self, $class
}

sub DESTROY {}

sub AUTOLOAD
{
    my $self = $_[0];
    my $func = $AUTOLOAD;
    $func =~ s/.*:://;
    my ($function, $criterion) = $func =~ /^(add|get)_(.*)/;
    croak "Undefined subroutine $func called"
        unless $criterion &&
               grep $_ eq $criterion, @Devel::Cover::DB::Criteria,
                                      qw( sub_name file line );
    no strict "refs";
    if ($function eq "get")
    {
        my $c = $criterion eq "time" ? "statement" : $criterion;
        if (grep $_ eq $c, qw( sub_name file line ))
        {
            *$func = sub
            {
                my $self = shift;
                $self->{$c}
            }
        }
        else
        {
            *$func = sub
            {
                my $self = shift;
                my $file = shift;
                $file = "" unless defined $file;
                $self->{f}{$file}{$c}
            }
        };
    }
    else
    {
        *$func = sub
        {
            my $self = shift;
            my $file = shift;
            push @{$self->{f}{$file}{$criterion}}, @_;
        };
    }
    goto &$func
}

sub add_criteria
{
    my $self = shift;
    @{$self->{criteria}}{@_} = ();
    $self
}

sub criteria
{
    my $self = shift;
    keys %{$self->{criteria}}
}

sub set_subroutine
{
    my $self = shift;
    my ($sub_name, $file, $line) = @{$self}{qw( sub_name file line )} = @_;
    $self->{additional} = 0;
    if ($self->reuse($file))
    {
        # reusing a structure
        if (exists $self->{f}{$file}{start}{$line}{$sub_name})
        {
            # sub already exists - normal case
            # print STDERR "reuse $file:$line:$sub_name\n";
            $self->{count}{$_}{$file} =
                $self->{f}{$file}{start}{$line}{$sub_name}{$_}
                for $self->criteria;
        }
        else
        {
            # sub doesn't exist, for example a conditional C<eval "use M">
            $self->{additional} = 1;
            if (exists $self->{additional_count}{($self->criteria)[0]}{$file})
            {
                # already had such a sub in module
                # print STDERR "reuse additional $file:$line:$sub_name\n";
                $self->{count}{$_}{$file} =
                    $self->{f}{$file}{start}{$line}{$sub_name}{$_} =
                    ($self->add_count($_))[0]
                    for $self->criteria;
            }
            else
            {
                # first such a sub in module
                # print STDERR "reuse first $file:$line:$sub_name\n";
                $self->{count}{$_}{$file} =
                    $self->{additional_count}{$_}{$file} =
                    $self->{f}{$file}{start}{$line}{$sub_name}{$_} =
                    $self->{f}{$file}{start}{-1}{"__COVER__"}{$_}
                    for $self->criteria;
            }
        }
    }
    else
    {
        # first time sub seen in new structure
        # print STDERR "new $file:$line:$sub_name\n";
        $self->{count}{$_}{$file} =
            $self->{f}{$file}{start}{$line}{$sub_name}{$_} =
            $self->get_count($_)
            for $self->criteria;
    }
    # use Data::Dumper; $Data::Dumper::Indent = 1; $Data::Dumper::Sortkeys = 1;
    # print Dumper $self->{f}{$file}{start};
}

sub store_counts
{
    my $self = shift;
    my ($file) = @_;
    # $self->set_subroutine("__COVER__", $file, -1);
    $self->{count}{$_}{$file} =
        $self->{f}{$file}{start}{-1}{__COVER__}{$_} =
        $self->get_count($_)
        for $self->criteria;
    # use Data::Dumper; $Data::Dumper::Indent = 1; $Data::Dumper::Sortkeys = 1;
    # print Dumper $self->{f}{$file}{start};
}

sub reuse
{
    my $self = shift;
    my ($file) = @_;
    exists $self->{f}{$file}{start}{-1}{"__COVER__"}
}

sub set_file
{
    my $self = shift;
    ($self->{file}) = @_;
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
    $self->{f}{$file}{digest} = $digest;
}

sub get_count
{
    my $self = shift;
    my ($criterion) = @_;
    $self->{count}{$criterion}{$self->{file}}
}

sub add_count
{
    my $self = shift;
    my ($criterion) = @_;
    $self->{additional_count}{$criterion}{$self->{file}}++
        if $self->{additional};
    ($self->{count}{$criterion}{$self->{file}}++,
     !$self->reuse($self->{file}) || $self->{additional})
}

sub delete_file
{
    my $self = shift;
    my ($file) = @_;
    delete $self->{f}{$file};
}

sub write
{
    my $self = shift;
    my ($dir) = @_;
    # use Data::Dumper; print Dumper $self;
    $dir .= "/structure";
    unless (-d $dir)
    {
        mkdir $dir, 0777 or croak "Can't mkdir $dir: $!\n";
    }
    for my $file (sort keys %{$self->{f}})
    {
        $self->{f}{$file}{file} = $file;
        unless ($self->{f}{$file}{digest})
        {
            warn "Can't find digest for $file";
            next;
        }
        my $df = "$dir/$self->{f}{$file}{digest}";
        # TODO - determine if Structure has changed to save writing it.
        # my $f = $df; my $n = 1; $df = $f . "." . $n++ while -e $df;
        Storable::nstore($self->{f}{$file}, $df); # unless -e $df;
    }
}

sub read
{
    my $self     = shift;
    my ($digest) = @_;
    my $file     = "$self->{base}/structure/$digest";
    my $s        = retrieve($file);
    $self->{f}{$s->{file}} = $s;
    $self
}

sub read_all
{
    my ($self) = @_;
    my $dir = $self->{base};
    $dir .= "/structure";
    opendir D, $dir or return;
    for my $d (grep $_ !~ /\./, readdir D)
    {
        $self->read($d);
    }
    closedir D or die "Can't closedir $dir: $!";
    $self
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

Version 0.53 - 17th April 2005

=head1 LICENCE

Copyright 2004-2005, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

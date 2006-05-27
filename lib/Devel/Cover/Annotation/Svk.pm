# Copyright 2005-2006, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Annotation::Svk;

use strict;
use warnings;

our $VERSION = "0.55";

use Getopt::Long;
use Digest::MD5;

sub md5_fh
{
    my $fh = shift;
    my $ctx = Digest::MD5->new;
    $ctx->addfile($fh);
    $ctx->hexdigest
}

sub new
{
    my $class = shift;
    my $annotate_arg = $ENV{DEVEL_COVER_SVK_ANNOTATE} || "";
    my $self =
    {
        annotations => [ qw( version author date ) ],
        command     => "svk annotate $annotate_arg [[file]]",
        @_
    };

    bless $self, $class;

    open my $c, "-|", "svk info"
        or warn "cover: Not a svk checkout: $!\n", return;
    while (<$c>)
    {
        chomp;
        next unless s/^Depot Path: //;
        $self->{depotbase} = $_;
        last;
    }

    open $c, "-|", "svk ls -Rf $self->{depotbase}"
        or warn "cover: Can't run svk ls: $!\n", return;
    while (<$c>)
    {
        chomp;
        s{^\Q$self->{depotbase}\E/}{};
        next unless -f $_;

        open my $f, $_ or warn "cover: Can't open $_: $!\n", next;
        $self->{md5map}{md5_fh($f)} = $_;
    }

    $self
}

sub get_annotations
{
    my $self = shift;
    my ($file) = @_;

    return if exists $self->{_annotations}{$file};
    my $a = $self->{_annotations}{$file} = [];

    print "cover: Getting svk annotation information for $file\n";

    open my $fh, $file or warn "cover: Can't open file $file: $!\n", return;
    my $realfile = $self->{md5map}{md5_fh($fh)}
        or warn "cover: $file is not under svk control\n", return;

    my $command = $self->{command};
    $command =~ s/\[\[file\]\]/$realfile/g;
    open my $c, "-|", $command
        or warn "cover: Can't run $command: $!\n", return;
    <$c>; <$c>;  # ignore first two lines
    while (<$c>)
    {
        my @a = /(\d+)\s*\(\s*(\S+)\s*(.*?)\):/;
        # hack for linking the revision number
        $a[0] = qq|<a href="$ENV{SVNWEB_URL}/revision/?rev=$a[0]">$a[0]</a>|
            if $ENV{SVNWEB_URL};
        push @$a, \@a;
    }
    close $c or warn "cover: Failed running $command: $!\n"
}

sub get_options
{
    my ($self, $opt) = @_;
    $self->{$_} = 1 for @{$self->{annotations}};
    die "Bad option" unless
        GetOptions($self,
                   qw(
                       author
                       command=s
                       date
                       version
                     ));
}

sub count
{
    my $self = shift;
    $self->{author} + $self->{date} + $self->{version}
}

sub header
{
    my $self = shift;
    my ($annotation) = @_;
    $self->{annotations}[$annotation]
}

sub width
{
    my $self = shift;
    my ($annotation) = @_;
    (7, 10, 10)[$annotation]
}

sub text
{
    my $self = shift;
    my ($file, $line, $annotation) = @_;
    return "" unless $line;
    $self->get_annotations($file);
    $self->{_annotations}{$file}[$line - 1][$annotation]
}

sub error
{
    my $self = shift;
    my ($file, $line, $annotation) = @_;
    0
}

sub class
{
    my $self = shift;
    my ($file, $line, $annotation) = @_;
    ""
}

1

__END__

=head1 NAME

Devel::Cover::Annotation::Svk - Annotate with svk information

=head1 SYNOPSIS

 cover -report xxx -annotation svk

=head1 DESCRIPTION

Annotate coverage reports with svk annotation information.
This module is designed to be called from the C<cover> program.

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 VERSION

Version 0.55 - 22nd September 2005

=head1 LICENCE

Copyright 2005-2006, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

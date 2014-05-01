# Copyright 2005-2014, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Annotation::Git;

use strict;
use warnings;

# VERSION

use Getopt::Long;

sub new {
    my $class = shift;
    my $annotate_arg = $ENV{DEVEL_COVER_GIT_ANNOTATE} || "";
    my $self = {
        annotations => [ qw( version author date ) ],
        command     => "git blame --porcelain $annotate_arg [[file]]",
        @_
    };

    bless $self, $class
}

sub get_annotations {
    my $self = shift;
    my ($file) = @_;

    return if exists $self->{_annotations}{$file};
    my $a = $self->{_annotations}{$file} = [];

    print "cover: Getting git annotation information for $file\n";

    my $command = $self->{command};
    $command =~ s/\[\[file\]\]/$file/g;
    # print "Running [$command]\n";
    open my $c, "-|", $command
        or warn "cover: Can't run $command: $!\n", return;
    my @a;
    my $start = 1;
    while (<$c>) {
        # print "[$_]\n";
        if (/^\t/) {
            push @$a, [@a];
            $start = 1;
            next;
        }

        if ($start == 1) {
            $a[0] = substr $1, 0, 8 if /^(\w+)/;
            $start = 0;
        } else {
            $a[1] = $1 if /^author (.*)/;
            $a[2] = localtime $1 if /^author-time (.*)/;
        }
    }
    close $c or warn "cover: Failed running $command: $!\n"
}

sub get_options {
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

sub count {
    my $self = shift;
    $self->{author} + $self->{date} + $self->{version}
}

sub header {
    my $self = shift;
    my ($annotation) = @_;
    $self->{annotations}[$annotation]
}

sub width {
    my $self = shift;
    my ($annotation) = @_;
    (8, 16, 24)[$annotation]
}

sub text {
    my $self = shift;
    my ($file, $line, $annotation) = @_;
    return "" unless $line;
    $self->get_annotations($file);
    $self->{_annotations}{$file}[$line - 1][$annotation]
}

sub error {
    my $self = shift;
    my ($file, $line, $annotation) = @_;
    0
}

sub class {
    my $self = shift;
    my ($file, $line, $annotation) = @_;
    ""
}

1

__END__

=head1 NAME

Devel::Cover::Annotation::Git - Annotate with git information

=head1 SYNOPSIS

 cover -report text -annotation git  # Or any other report type

=head1 DESCRIPTION

Annotate coverage reports with git annotation information.
This module is designed to be called from the C<cover> program.

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2005-2014, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

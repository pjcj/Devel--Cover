# Copyright 2005-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Annotation::Git;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use Getopt::Long qw( GetOptions );

sub new ($class, @args) {
  my $annotate_arg = $ENV{DEVEL_COVER_GIT_ANNOTATE} || "";
  my $self         = {
    annotations => [qw( version author date )],
    command     => "git blame --porcelain $annotate_arg [[file]]",
    @args,
  };

  bless $self, $class
}

sub get_annotations ($self, $file) {
  return if exists $self->{_annotations}{$file};
  my $annotations = $self->{_annotations}{$file} = [];

  print "cover: Getting git annotation information for $file\n";

  my $command = $self->{command};
  $command =~ s/\[\[file\]\]/$file/g;
  # print "Running [$command]\n";
  open my $c, "-|", $command or warn("cover: Can't run $command: $!\n"), return;
  my @annotation;
  my $start = 1;
  while (my $line = <$c>) {
    # print "[$_]\n";
    if ($line =~ /^\t/) {
      push @$annotations, [@annotation];
      $start = 1;
      next;
    }

    if ($start == 1) {
      $annotation[0] = substr $1, 0, 8 if $line =~ /^(\w+)/;
      $start = 0;
    } else {
      $annotation[1] = $1 if $line =~ /^author (.*)/;
      if ($line =~ /^author-time (.*)/) { $annotation[2] = localtime $1 }
    }
  }
  close $c or warn "cover: Failed running $command: $!\n"
}

sub get_options ($self, $opt) {
  $self->{$_} = 1 for $self->{annotations}->@*;
  die "Bad option" unless GetOptions(
    $self, qw(
      author
      command=s
      date
      version
    ),
  );
}

sub count ($self) {
  $self->{author} + $self->{date} + $self->{version}
}

sub header ($self, $annotation) {
  $self->{annotations}[$annotation]
}

sub width ($self, $annotation) {
  (8, 16, 24)[$annotation]
}

sub text ($self, $file, $line, $annotation) {
  return "" unless $line;
  $self->get_annotations($file);
  $self->{_annotations}{$file}[$line - 1][$annotation]
}

sub error ($self, $file, $line, $annotation) { 0 }
sub class ($self, $file, $line, $annotation) { "" }

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Annotation::Git - Annotate with git information

=head1 SYNOPSIS

 cover -report text -annotation git  # Or any other report type

=head1 DESCRIPTION

Annotate coverage reports with git annotation information.
This module is designed to be called from the C<cover> program.

=head1 SEE ALSO

 Devel::Cover

=head1 LICENCE

Copyright 2005-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

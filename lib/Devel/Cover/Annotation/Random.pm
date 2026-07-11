# Copyright 2004-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Annotation::Random;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use Getopt::Long qw( GetOptions );

sub new ($class, @args) { bless {@args}, $class }

sub get_options ($self, $opt) {
  $self->{count} = 1;
  die "Bad option" unless GetOptions(
    $self, qw(
      count=s
    ),
  );
}

sub count  ($self)              { $self->{count} }
sub header ($self, $annotation) { "rnd$annotation" }
sub width  ($self, $annotation) { length $self->header($annotation) }

sub text ($self, $file, $line, $annotation) {
  return "" unless $line;
  $self->{annotation}{$file}[$line][$annotation] = int rand 10
    unless defined $self->{annotation}{$file}[$line][$annotation];
  $self->{annotation}{$file}[$line][$annotation]
}

sub error ($self, $file, $line, $annotation) {
  !$self->text($file, $line, $annotation)
}

sub class ($self, $file, $line, $annotation) {
  return "" unless $line;
  "c" . int(($self->text($file, $line, $annotation) + 2) / 3)
}

"
I don't know what to do, and I'm always in the dark
We're living in a powder keg and giving off sparks
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Annotation::Random - Example annotation for formatters

=head1 SYNOPSIS

 cover -report text -annotation random -count 3  # Or any other report type

=head1 DESCRIPTION

This module provides an example annotation.
It is designed to be called from the C<cover> program.

=head1 SEE ALSO

 Devel::Cover

=head1 LICENCE

Copyright 2004-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

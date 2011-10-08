# Copyright 2001-2011, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Criterion;

use strict;
use warnings;

use Devel::Cover::Statement      ;
use Devel::Cover::Branch         ;
use Devel::Cover::Condition      ;
use Devel::Cover::Condition_or_2 ;
use Devel::Cover::Condition_or_3 ;
use Devel::Cover::Condition_and_2;
use Devel::Cover::Condition_and_3;
use Devel::Cover::Condition_xor_4;
use Devel::Cover::Subroutine     ;
use Devel::Cover::Time           ;
use Devel::Cover::Pod            ;

sub coverage    { $_[0][0] }
sub information { $_[0][1] }

sub covered     { "n/a" }
sub total       { "n/a" }
sub percentage  { "n/a" }
sub error       { "n/a" }
sub text        { "n/a" }
sub values      { [ $_[0]->covered ] }
sub criterion   { require Carp; Carp::confess("criterion() must be overridden") }

sub calculate_percentage
{
    my $class = shift;
    my ($db, $s) = @_;
    my $errors = $s->{error} || 0;
    $s->{percentage} = $s->{total} ? 100 - $errors * 100 / $s->{total} : 100;
}

sub aggregate {
    my ($self, $s, $file, $keyword, $t) = @_;

    my $name = $self->criterion;
    $t = int($t);
    $s->{$file}{$name}{$keyword} += $t;
    $s->{$file}{total}{$keyword} += $t;
    $s->{Total}{$name}{$keyword} += $t;
    $s->{Total}{total}{$keyword} += $t;
}

sub calculate_summary
{
    my $self = shift;
    my ($db, $file) = @_;

    my $s = $db->{summary};
    $self->aggregate($s, $file, "total",       $self->total);
    $self->aggregate($s, $file, "uncoverable", 1) if $self->uncoverable;
    $self->aggregate($s, $file, "covered",     1) if $self->covered;
    $self->aggregate($s, $file, "error",       1) if $self->error;
}


1

__END__

=head1 NAME

Devel::Cover::Criterion - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Criterion;

=head1 DESCRIPTION

Abstract base class for all the coverage criteria.

=head1 SEE ALSO

 Devel::Cover

=head1 METHODS

=head2 new

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2001-2011, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

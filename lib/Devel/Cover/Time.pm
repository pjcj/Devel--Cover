# Copyright 2001-2004, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Time;

use strict;
use warnings;

our $VERSION = "0.49";

use base "Devel::Cover::Criterion";

sub covered    { ${$_[0]} }
sub total      { 1 }
sub percentage { ${$_[0]} ? 100 : 0 }
sub error      { 0 }

sub calculate_summary
{
    my $self = shift;
    my ($db, $file) = @_;

    $db->{summary}{$file}{time}{total} += $$self;
    $db->{summary}{Total}{time}{total} += $$self;
}

sub calculate_percentage
{
    my $class = shift;
    my ($db, $s) = @_;
    my $t = $db->{summary}{Total}{time}{total};
    $s->{percentage} = $t ? $s->{total} * 100 / $t : 100;
}

1

__END__

=head1 NAME

Devel::Cover::Time - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Time;

=head1 DESCRIPTION

Module for storing time coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

=head2 new

 my $db = Devel::Cover::DB->new(db => "my_coverage_db");

Contructs the DB from the specified database.

=head1 BUGS

Huh?

=head1 VERSION

Version 0.49 - 6th October 2004

=head1 LICENCE

Copyright 2001-2004, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

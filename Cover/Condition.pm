# Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Condition;

use strict;
use warnings;

use base "Devel::Cover::Criterion";

our $VERSION = "0.14";

sub covered    { scalar grep $_, @{$_[0]} }
sub total      { scalar @{$_[0]} }
sub percentage
{
    sprintf "%5.2f", $_[0]->total ? $_[0]->covered / $_[0]->total * 100 : 100
}
sub error      { scalar grep !$_, @{$_[0]} }

sub calculate_summary
{
    my $self = shift;
    my ($db, $file) = @_;

    my $s = $db->{summary};

    my $t = @$self;
    my $c = grep { $_ } @$self;

    $s->{$file}{condition}{total}   += $t;
    $s->{$file}{total}{total}       += $t;
    $s->{Total}{condition}{total}   += $t;
    $s->{Total}{total}{total}       += $t;

    $s->{$file}{condition}{covered} += $c;
    $s->{$file}{total}{covered}     += $c;
    $s->{Total}{condition}{covered} += $c;
    $s->{Total}{total}{covered}     += $c;
}

1

__END__

=head1 NAME

Devel::Cover::Condition - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Condition;

=head1 DESCRIPTION

This module provides ...

=head1 SEE ALSO

 Devel::Cover

=head1 METHODS

=head2 new

 my $db = Devel::Cover::DB->new(db => "my_coverage_db");

Contructs the DB from the specified database.

=head1 BUGS

Huh?

=head1 VERSION

Version 0.14 - 28th February 2002

=head1 LICENCE

Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

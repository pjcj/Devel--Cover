# Copyright 2001, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Pod;

use strict;
use warnings;

use base "Devel::Cover::Criterion";

our $VERSION = "0.11";

sub covered    { $_[0]->[0] ? 1 : 0 }
sub total      { 1 }
sub percentage { $_[0]->[0] ? 100 : 0 }
sub error      { !$_[0]->[0] }

1

__END__

=head1 NAME

Devel::Cover::Pod - Code coverage metrics for Perl

=head1 SYNOPSIS

 use Devel::Cover::Pod;

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

Version 0.11 - 10th September 2001

=head1 LICENCE

Copyright 2001, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

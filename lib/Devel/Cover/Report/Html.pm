# Copyright 2001-2003, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Report::Html;

use strict;
use warnings;

our $VERSION = "0.22";

use Devel::Cover::Report::Html_subtle 0.22;

sub report
{
    my ($pkg, $db, $options) = @_;

    Devel::Cover::Report::Html_subtle->report($db, $options)
}

1;

__END__

=head1 NAME

Devel::Cover::Report::Html - Backend for HTML reporting of coverage
statistics

=head1 SYNOPSIS

 use Devel::Cover::Report::Html;

 Devel::Cover::Report::Html->report($db, $options);

=head1 DESCRIPTION

This module provides a HTML reporting mechanism for coverage data.  It
is designed to be called from the C<cover> program.  This is a simple
wrapper around the default HTML ooutput module.

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 VERSION

Version 0.22 - 2nd September 2003

=head1 LICENCE

Copyright 2001-2003, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

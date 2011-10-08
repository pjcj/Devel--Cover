# Copyright 2001-2011, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Report::Html;

use strict;
use warnings;

use base "Devel::Cover::Report::Html_minimal";

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
is designed to be called from the C<cover> program.  This is an empty
class derived from the default HTML output module,
Devel::Cover::Report::Html_minimal.

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2001-2011, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

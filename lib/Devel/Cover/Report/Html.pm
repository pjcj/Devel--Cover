# Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Report::Html;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use parent "Devel::Cover::Report::Html_crisp";

1;

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Report::Html - HTML backend for Devel::Cover

=head1 SYNOPSIS

 cover -report html

=head1 DESCRIPTION

This module provides a HTML reporting mechanism for coverage data.  It
is designed to be called from the C<cover> program.  This is an empty
class derived from the default HTML output module,
Devel::Cover::Report::Html_crisp.

=head1 SEE ALSO

 Devel::Cover

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

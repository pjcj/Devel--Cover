# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# Simulates an installed AutoLoader module with stale blib #line paths.

package Autoloader_stale;

use strict;
use warnings;

use AutoLoader qw( AUTOLOAD );

sub loaded { 42 }

1;

__END__

sub stale { 18 }

1;

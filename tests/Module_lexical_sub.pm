# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Module_lexical_sub;

use strict;
use warnings;
use feature 'lexical_subs';
no warnings 'experimental::lexical_subs';

# A my sub keeps its prototype in the padname's PROTOCV, reachable from 5.22
my sub helper {
  my $x = shift;
  my $y = $x * 3;
  $y + 1
}

my $result = helper(7);

sub get { $result }

1;

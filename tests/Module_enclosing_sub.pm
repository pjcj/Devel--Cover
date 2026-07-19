# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Module_enclosing_sub;

use strict;
use warnings;
use feature 'lexical_subs';
no warnings 'experimental::lexical_subs';

# A sub that lexically encloses a my sub compiles with an introcv/clonecv
# prologue, which check_file and sub_info must step past or the enclosing
# sub is dropped from coverage entirely along with its body

sub named_enc {
  my sub inner { my $x = shift; $x + 5 }
  inner(shift)
}

my $anon_enc = sub {
  my sub inner { my $x = shift; $x + 7 }
  inner(shift)
};

sub nested_enc {
  my sub mid {
    my sub deep { my $x = shift; $x + 9 }
    deep(shift)
  }
  mid(shift)
}

sub plain { my $x = shift; $x + 1 }

sub run_anon { $anon_enc->(shift) }

1;

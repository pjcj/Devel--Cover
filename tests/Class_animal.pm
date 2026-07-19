# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Class_animal;
use 5.38.0;
use feature "class";
no warnings "experimental::class";

class Animal {
  field $name :param;
  field $sound :param = "...";

  ADJUST { $name = ucfirst $name }

  method name   { $name }
  method speak  { "$name says $sound" }
  method unused { "never called" }
}

1;

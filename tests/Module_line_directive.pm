# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Module_line_directive;

my $count = 0;
$count = $count + 1;
if ($count > 0) {
  $count = $count + 10;
}

sub get_count { $count }

# The module exits under a #line directive naming another file, as Template
# Toolkit's generated parsers do.  The require-tree capture identifies the
# tree by its own first cop, not the last statement executed, so the
# top-level statements above stay covered even though the last cop is filed
# elsewhere.  This return belongs to Parser.yp and is filtered from the
# report.
#line 500 "Parser.yp"
return 1

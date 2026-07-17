# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Module_top_level;

my $count = 0;
$count = $count + 1;
for my $i (1 .. 3) {
  $count += $i;
}
if ($count > 2) {
  $count *= 2;
} else {
  $count = 0;
}

my $add = sub {
  my ($x, $y) = @_;
  $x + $y
};

my $unused = sub {
  my ($x) = @_;
  $x * 2
};

my $outer = sub {
  my $inner = sub {
    my ($x) = @_;
    $x + 1
  };
  my $inner_unused = sub {
    my ($x) = @_;
    $x - 1
  };
  $inner->(2)
};

sub get_count { $count }
sub add       { $add->(1, 2) }
sub run_outer { $outer->() }

1

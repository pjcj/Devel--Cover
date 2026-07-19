# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Module_top_level;

# An anon in a BEGIN block's pad is reachable only through that pad
my $begin_anon;
BEGIN {
  $begin_anon = sub {
    my ($x) = @_;
    $x + 100
  };
}

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
    my $inner_inner = sub {
      my ($y) = @_;
      my $inner_inner_inner = sub {
        my ($z) = @_;
        $z * 2
      };
      $inner_inner_inner->($y) + 1
    };
    $inner_inner->($x) + 1
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
sub run_begin { $begin_anon->(5) }

# Exit via a top-level return.  pp_return unwinds the require's eval
# context and tail-calls pp_leaveeval directly, so the leaveeval op never
# runs and the return hook must capture the tree instead.
return 1

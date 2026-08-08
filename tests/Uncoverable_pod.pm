# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Uncoverable_pod;

sub documented { "documented" }

sub excused_pod {
  # uncoverable pod
  "excused";
}

sub stale_pod {
  # uncoverable pod
  "stale";
}

sub never_called {
  # uncoverable subroutine
  # uncoverable statement
  # uncoverable pod
  die "never called";
}

1

__END__

=head2 documented

A documented subroutine.

=cut

=head2 stale_pod

A documented subroutine whose pod marker is stale.

=cut

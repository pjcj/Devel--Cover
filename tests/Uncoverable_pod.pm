# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Uncoverable_pod;

sub documented { "documented" }

# dc uncoverable pod
sub excused_pod {
  "excused";
}

# dc uncoverable pod
sub stale_pod {
  "stale";
}

# dc uncoverable subroutine
# dc uncoverable pod
sub never_called {
  # dc uncoverable statement
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

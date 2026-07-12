package GitHook;

use v5.26.0;
use warnings;
use experimental "signatures";

use Exporter qw( import );

our @EXPORT_OK = qw( get_current_branch on_main ticket_re );

sub ticket_re () { qr/[A-Z]{2,8}-\d+/ }

sub get_current_branch () {
  my $branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null` // "";
  chomp $branch;
  $branch
}

sub on_main () { get_current_branch eq "main" }

"
And you're only smiling
When you play your violin
"

__END__

=pod

=head1 NAME

GitHook - shared helpers for the git commit-message hooks

=head1 SYNOPSIS

  use GitHook qw( get_current_branch on_main ticket_re );

  my $branch = get_current_branch;
  exit 0 if on_main;

  my $re = ticket_re;
  $branch =~ /^($re)/ or warn "branch has no ticket reference\n";

=head1 DESCRIPTION

An L<Exporter>-based module holding the git helpers shared by the
C<commit-msg> and C<prepare-commit-msg> hooks, so the branch name and
ticket-reference logic live in one place. Nothing is exported by default;
request each function explicitly.

=head1 FUNCTIONS

=head2 ticket_re

Return a compiled regexp matching a ticket reference: two to eight uppercase
letters, a hyphen, then digits, for example C<GH-56>. The pattern has no
anchors or captures, so a caller can embed it in a larger match.

=head2 get_current_branch

Return the name of the current git branch, or the empty string if it cannot
be determined, for example outside a repository or on a detached HEAD.

=head2 on_main

Return true if the current branch is C<main>.

=head1 AUTHOR

Paul Johnson <paul@pjcj.net>

=head1 LICENCE

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

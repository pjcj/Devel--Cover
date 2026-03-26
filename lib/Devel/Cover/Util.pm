# Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Util;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use Cwd        qw( abs_path );
use Exporter   qw( import );
use File::Spec ();

our @EXPORT_OK = qw( remove_contained_paths );

sub remove_contained_paths ($container, @paths) {
  my ($drive) = File::Spec->splitpath($container);
  my $ignore_case = "(?i)";
  $ignore_case = "" if !File::Spec->case_tolerant($drive);

  my $regex = qr[
      $ignore_case
      ^ \Q$container\E ($|/)
    ]x;

  grep { (abs_path $_) !~ $regex } @paths
}

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Util - Utility subroutines for Devel::Cover

=head1 SYNOPSIS

 use Devel::Cover::Util qw( remove_contained_paths );

 # Remove paths that fall inside the current directory
 my @filtered = remove_contained_paths(getcwd, @Inc);

=head1 DESCRIPTION

This module provides utility subroutines for Devel::Cover.  All functions are
importable on request via L<Exporter>.

=head1 SUBROUTINES

=head2 remove_contained_paths

 my @outside = remove_contained_paths($container, @paths);

Return the elements of C<@paths> that are B<not> inside C<$container>.  A path
is considered "inside" the container when its L<Cwd/abs_path> starts with
C<$container> followed by a C</> or the end of the string.  The trailing-slash
check prevents false positives when a directory name is a prefix of a sibling
(e.g. C</opt/app> should not match C</opt/appdata>).

Case sensitivity is determined per-drive via L<File::Spec/case_tolerant>.  On
Windows this is evaluated for the drive letter of C<$container>; on Unix and
macOS systems C<File::Spec> uses a compile-time heuristic which may not reflect
the actual filesystem (e.g. case-insensitive APFS), but is the best available
without probing the mount point.

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

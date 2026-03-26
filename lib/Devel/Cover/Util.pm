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
use List::Util qw( any min );

our @EXPORT_OK = qw( common_prefix remove_contained_paths );

sub common_prefix (@files) {
  my @paths = grep { $_ ne "Total" } @files;
  return ("", { map { $_ => $_ } @files }) if @paths < 2;

  my @split = map { [ split m|/| ] } @paths;
  my $min   = min(map { scalar @$_ } @split);

  # stop before the last component - it is the filename, not a directory
  my $limit  = $min - 1;
  my $shared = 0;
  for my $i (0 .. $limit - 1) {
    last if any { $_->[$i] ne $split[0][$i] } @split[ 1 .. $#split ];
    $shared++;
  }

  my $prefix = join("/", $split[0]->@[ 0 .. $shared - 1 ]) . "/";

  # bare "/" or empty is not a meaningful prefix
  return ("", { map { $_ => $_ } @files }) if $shared < 1 || $prefix eq "/";

  my $plen  = length $prefix;
  my %short = map { $_ => substr $_, $plen } @paths;
  $short{Total} = "Total" if any { $_ eq "Total" } @files;

  ($prefix, \%short)
}

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

"
Master!
Apprentice!
Heartborne, 7th Seeker
Warrior!
Disciple!
In me the Wishmaster
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Util - Utility subroutines for Devel::Cover

=head1 SYNOPSIS

 use Devel::Cover::Util qw( common_prefix remove_contained_paths );

 # Strip the shared directory prefix from a list of files
 my ($prefix, $short) = common_prefix(@files);

 # Remove paths that fall inside the current directory
 my @filtered = remove_contained_paths(getcwd, @Inc);

=head1 DESCRIPTION

This module provides utility subroutines for Devel::Cover.  All functions are
importable on request via L<Exporter>.

=head1 SUBROUTINES

=head2 common_prefix (@files)

 my ($prefix, $short) = common_prefix(@files);

Compute the longest common directory prefix shared by all C<@files>.  Returns a
two-element list: the prefix string (with trailing C</>) and a hashref mapping
each original path to its shortened suffix.

If the common prefix has fewer than two path components (e.g. bare C</> or
empty), an empty prefix is returned and every path maps to itself.

Entries equal to C<"Total"> are passed through unchanged and excluded from the
prefix calculation.

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

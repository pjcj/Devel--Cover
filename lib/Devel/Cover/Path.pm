# Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Path;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use Exporter   qw( import );
use File::Spec ();            ## no perlimports
use List::Util qw( any min );

our @EXPORT_OK = qw( common_prefix output_path );

sub common_prefix (@files) {
  my @paths = grep $_ ne "Total", @files;
  return ("", { map { $_ => $_ } @files }) if @paths < 2;

  my @split = map { [split m|/|] } @paths;
  my $min   = min(map scalar @$_, @split);

  # stop before the last component - it is the filename, not a directory
  my $limit  = $min - 1;
  my $shared = 0;
  for my $i (0 .. $limit - 1) {
    last if any { $_->[$i] ne $split[0][$i] } @split[1 .. $#split];
    $shared++;
  }

  my $prefix = join("/", $split[0]->@[0 .. $shared - 1]) . "/";

  # bare "/" or empty is not a meaningful prefix
  return ("", { map { $_ => $_ } @files }) if $shared < 1 || $prefix eq "/";

  my $plen  = length $prefix;
  my %short = map { $_ => substr $_, $plen } @paths;
  $short{Total} = "Total" if any { $_ eq "Total" } @files;

  ($prefix, \%short)
}

sub output_path ($outputdir, $file, $spec = "File::Spec") {
  $spec->file_name_is_absolute($file)
    ? $file
    : $spec->catfile($outputdir, $file)
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

Devel::Cover::Path - Path manipulation subroutines for Devel::Cover

=head1 SYNOPSIS

 use Devel::Cover::Path qw( common_prefix output_path );

 # Strip the shared directory prefix from a list of files
 my ($prefix, $short) = common_prefix(@files);

 # Place a report file under the output directory unless it is absolute
 my $path = output_path($outputdir, $file);

=head1 DESCRIPTION

This module provides path manipulation subroutines for Devel::Cover.  All
functions are importable on request via L<Exporter>.

=head1 SUBROUTINES

=head2 common_prefix (@files)

 my ($prefix, $short) = common_prefix(@files);

Compute the longest directory prefix common to all C<@files>.  Returns a
two-element list: the prefix string (with trailing C</>) and a hashref mapping
each original path to its shortened suffix.

If the common prefix has fewer than two path components (e.g. bare C</> or
empty), an empty prefix is returned and every path maps to itself.

Entries equal to C<"Total"> are passed through unchanged and excluded from the
prefix calculation.

=head2 output_path ($outputdir, $file, $spec)

 my $path = output_path($outputdir, $file);

Return C<$file> when it is an absolute path, and C<$file> joined under
C<$outputdir> otherwise.

C<$spec> is the L<File::Spec> class to ask, so that tests can check the rules
of another platform.  It defaults to C<File::Spec>.

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
L<https://pjcj.net>

=cut

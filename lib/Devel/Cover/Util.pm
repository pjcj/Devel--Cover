# Copyright 2001-2018, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Util;

use strict;
use warnings;

# VERSION

use Cwd "abs_path";
use File::Spec;
use base "Exporter";

our @EXPORT_OK = qw( remove_contained_paths );

sub remove_contained_paths {
    my ($container, @paths) = @_;

    # File::Spec's case tolerancy detection on *nix/Mac systems does not
    # take actual file system properties into account, but is better than
    # trying to normalise paths with per-os logic. On Windows it is
    # properly determined per drive.
    my ($drive) = File::Spec->splitpath($container);
    my $ignore_case = "(?i)";
    $ignore_case = "" if !File::Spec->case_tolerant($drive);

    my $regex = qr[
      $ignore_case      # ignore case on tolerant filesystems
      ^                 # string to match starts with:
      \Q$container\E    # path, meta-quoted for safety
      ($|/)             # followed by either the end of the string, or another
                        # slash, to avoid removing paths in directories named
                        # similar to the container
    ]x;

    @paths = grep {
        my $path = abs_path $_;    # normalise backslashes
        $path !~ $regex;           # check if path is inside the container
    } @paths;

    return @paths;
}

1

__END__

=head1 NAME

Devel::Cover::Util - Utility subroutines for Devel::Cover

=head1 SYNOPSIS

 use Devel::Cover::Util "remove_contained_paths";

=head1 DESCRIPTION

This module utility subroutines for Devel::Cover.

=head1 SUBROUTINES

=head2 remove_contained_paths

 @Inc = remove_contained_paths(getcwd, @Inc);

Remove certain paths from a list of paths.

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2001-2018, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

use strict;
use warnings;

package Devel::Cover::Util;

use Cwd 'abs_path';
use File::Spec;
use base 'Exporter';

our @EXPORT_OK = qw( remove_contained_paths );

sub remove_contained_paths {
    my ( $container, @paths ) = @_;

    # File::Spec's case tolerancy detection on *nix/Mac systems does not
    # take actual file system properties into account, but is better than
    # trying to normalize paths with per-os logic. On Windows it is
    # properly determined per drive.
    my ( $drive ) = File::Spec->splitpath( $container );
    my $ignore_case = '(?i)';
    $ignore_case = '' if !File::Spec->case_tolerant( $drive );

    my $regex = qr@
      $ignore_case      # ignore case on tolerant filesystems
      ^                 # string to match starts with:
      \Q$container\E    # path, meta-quoted for safety
      ($|/)             # followed by either the end of the string, or another
                        # slash, to avoid removing paths in directories named
                        # similar to the container
    @x;

    @paths = grep {
        my $path = abs_path $_;    # normalize backslashes
        $path !~ $regex;           # check if path is inside the container
    } @paths;

    return @paths;
}

1;

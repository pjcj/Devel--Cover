# Copyright 2001, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Process;

use strict;
use warnings;

use Exporter ();

our @ISA       = qw( Exporter );
our $VERSION   = "0.01";
our @EXPORT_OK = qw( cover_read );

sub cover_read
{
    my ($fh) = @_;
    local $/;
    my $cover;
    eval <$fh>;
    die $@ if $@;
    $cover
}

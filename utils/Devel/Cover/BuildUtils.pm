# Copyright 2010, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::BuildUtils;

use strict;
use warnings;

our $VERSION = "0.70";

use Exporter;

our @ISA       = "Exporter";
our @EXPORT_OK = qw(find_prove cpus prove_command);

sub find_prove
{
    my $perl = $^X;
    unless (-x $perl)
    {
        my ($dir) = grep -x "$_/$perl", split /:/, $ENV{PATH};
        $perl     = "$dir/$perl";
    }

    eval { $perl = readlink($perl) || $perl };
    # print "perl is [$perl]\n";
    my ($dir)    = $perl =~ m|(.*)/[^/]+|;
    my ($prove)  = grep -x, <$dir/prove*>;

    warn "prove cannot be found in $dir\n";

    $prove
}

sub cpus
{
    my $cpus = 1;
    eval { chomp ($cpus = `grep -c processor /proc/cpuinfo`); };
    $cpus
}

sub prove_command
{
    my $prove = find_prove or return;
    my $cpus  = cpus;
    $cpus-- if $cpus > 4;
    "$prove -brj$cpus t"
}

__END__

=head1 NAME

Devel::Cover::BuildUtils - Build utility functions for Devel::Cover

=head1 SYNOPSIS

 use Devel::Cover::BuildUtils "find_prove";

=head1 DESCRIPTION

Build utility functions for Devel::Cover.

=head1 SEE ALSO

 Devel::Cover

=head1 METHODS

=head1 BUGS

Huh?

=head1 VERSION

Version 0.70 - 29th August 2010

=head1 LICENCE

Copyright 2001-2010, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

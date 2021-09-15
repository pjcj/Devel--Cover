# Copyright 2010-2021, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::BuildUtils;

use strict;
use warnings;

# VERSION

use Exporter;

our @ISA       = "Exporter";
our @EXPORT_OK = qw(find_prove cpus nice_cpus njobs prove_command);

sub find_prove {
    my $perl = $^X;
    unless (-x $perl) {
        my ($dir) = grep -x "$_/$perl", split /:/, $ENV{PATH};
        $perl     = "$dir/$perl";
    }

    eval { $perl = readlink($perl) || $perl };
    # print "perl is [$perl]\n";
    my ($dir)    = $perl =~ m|(.*)/[^/]+|;
    my ($prove)  = grep -x, <$dir/prove*>;

    print "prove is in $dir\n";

    $prove
}

sub cpus {
    my $cpus = 1;
    eval { chomp ($cpus = `grep -c processor /proc/cpuinfo 2>/dev/null`) };
    $cpus || eval { ($cpus) = `sysctl hw.ncpu` =~ /(\d+)/ };
    $cpus || 1
}

sub nice_cpus {
    $ENV{DEVEL_COVER_CPUS} || do {
        my $cpus = cpus;
        $cpus-- if $cpus > 3;
        $cpus-- if $cpus > 6;
        $cpus
    }
}

sub njobs { nice_cpus }

sub prove_command {
    my $prove = find_prove or return;
    my $cpus  = nice_cpus;
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

=head1 LICENCE

Copyright 2001-2021, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

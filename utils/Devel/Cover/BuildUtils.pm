# Copyright 2010-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::BuildUtils;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use Exporter qw( import );

our @EXPORT_OK = qw( find_prove cpus nice_cpus njobs prove_command );

sub find_prove () {
  my $perl = $^X;
  unless (-x $perl) {
    my ($dir) = grep -x "$_/$perl", split /:/, $ENV{PATH};
    $perl = "$dir/$perl";
  }

  eval { $perl = readlink($perl) || $perl };
  my ($dir)   = $perl =~ m|(.*)/[^/]+|;
  my ($prove) = grep -x, <$dir/prove*>;

  say "prove is in $dir";

  $prove
}

sub cpus () {
  my $cpus = 1;
  eval { chomp($cpus = `grep -c processor /proc/cpuinfo 2>/dev/null`) };
  $cpus || eval { ($cpus) = `sysctl hw.ncpu` =~ /(\d+)/ };
  $cpus || 1
}

sub nice_cpus () {
  $ENV{DEVEL_COVER_CPUS} || do {
    my $cpus = cpus;
    $cpus-- if $cpus > 3;
    $cpus-- if $cpus > 6;
    $cpus
  }
}

sub njobs () { nice_cpus }

sub prove_command () {
  my $prove = find_prove or return;
  my $cpus  = nice_cpus;
  "$prove -brj$cpus t"
}

__END__

=encoding utf8

=head1 NAME

Devel::Cover::BuildUtils - Build utility functions for Devel::Cover

=head1 SYNOPSIS

 use Devel::Cover::BuildUtils qw(
   find_prove cpus nice_cpus njobs prove_command
 );

 my $prove = find_prove;     # path to prove executable
 my $n     = cpus;           # raw CPU count
 my $j     = nice_cpus;      # adjusted for comfort
 my $jobs  = njobs;          # alias for nice_cpus
 my $cmd   = prove_command;  # e.g. "/usr/bin/prove -brj3 t"

=head1 DESCRIPTION

This module provides helper functions used by the Devel::Cover build and test
infrastructure.  It locates the C<prove> binary that corresponds to the running
Perl, detects CPU count, and assembles a suitable C<prove> command line for
parallel test runs.

All functions are importable on request via L<Exporter>.

=head1 SUBROUTINES

=head2 find_prove

 my $prove = find_prove;

Locate the C<prove> executable that sits alongside the current C<$^X>.  Follows
symlinks on C<$^X> to find the real installation directory, then globs for
C<prove*> there.  Returns the path on success or C<undef> if no executable is
found.

=head2 cpus

 my $n = cpus;

Return the number of CPUs on the current machine.  Tries F</proc/cpuinfo>
(Linux) first, then C<sysctl hw.ncpu> (macOS/BSD).  Falls back to 1 if neither
method works.

=head2 nice_cpus

 my $n = nice_cpus;

Return a CPU count suitable for parallel work - slightly below L</cpus> to leave
headroom for the rest of the system.  Subtracts one core when more than three
are available and another when more than six are available.

Respects the C<DEVEL_COVER_CPUS> environment variable: if set, its value is
returned directly, bypassing the automatic calculation.

=head2 njobs

 my $n = njobs;

Alias for L</nice_cpus>.

=head2 prove_command

 my $cmd = prove_command;

Build a C<prove> command string for running the test suite in
parallel. Equivalent to:

 "<prove> -brj<nice_cpus> t"

Returns C<undef> if L</find_prove> fails.

=head1 ENVIRONMENT

=over

=item C<DEVEL_COVER_CPUS>

Override the number of parallel jobs used by L</nice_cpus> and
L</prove_command>.

=back

=head1 SEE ALSO

L<Devel::Cover>

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is isnt like plan skip )];

if ($^O eq "MSWin32") {
  plan skip_all => "utils/all_versions is not used on Windows";
}
unless (eval { require Parallel::Iterator }) {
  plan skip_all => "Parallel::Iterator required for utils/all_versions";
}

chdir "$FindBin::Bin/../.." or die "Can't chdir to the project root: $!";

sub run_all_versions (@args) {
  my $cmd = join " ", $^X, "utils/all_versions", @args;
  my $out = `$cmd 2>&1`;
  ($out, $? >> 8)
}

sub test_missing_version_fails () {
  my ($out, $exit)
    = run_all_versions(qw( -version 5.99.0 --dry_run make test ));
  isnt $exit, 0, "a run with no usable version exits non-zero";
  like $out, qr/5\.99\.0/, "the missing version is named";
}

sub test_list_still_exits_zero () {
  my ($out, $exit) = run_all_versions(qw( -version 5.99.0 --list ));
  is $exit, 0, "--list exits 0 with no usable version";
  like $out, qr/^Versions:/m, "--list prints the version list";
}

sub test_build_with_nothing_to_do_exits_zero () {
  my $bin = tempdir(CLEANUP => 1);
  open my $fh, ">", "$bin/dc-9.99.9" or die "Can't write $bin/dc-9.99.9: $!";
  print $fh "#!/bin/sh\nexit 0\n";
  close $fh or die "Can't close $bin/dc-9.99.9: $!";
  chmod 0755, "$bin/dc-9.99.9" or die "Can't chmod $bin/dc-9.99.9: $!";
  local $ENV{PATH} = "$bin:$ENV{PATH}";

  my ($out, $exit) = run_all_versions(qw( -version 9.99.9 --build --dry_run ));
  is $exit, 0, "--build with every version built exits 0";
  like $out, qr/already built/, "the no-op build is reported";
}

sub test_build_failure_exits_nonzero () {
  my ($out, $exit) = run_all_versions(qw( -version 5.99.0 --build --dry_run ));
  isnt $exit, 0, "a failed build exits non-zero";
  like $out, qr/Failed builds:.*\b5\.99\.0\b/, "the failed version is named";
  like $out, qr/5\.99\.0-thr/, "the failed thread variant is named";
}

sub test_build_success_exits_zero () {
  my ($dir)
    = grep { -d "$_/bin" && -d "$_-thr/bin" }
    glob "$ENV{HOME}/.plenv/versions/dc-5.*";
  my ($v) = ($dir // "") =~ m|/dc-(5\.\d+\.\d+)$|;
  SKIP: {
    skip "no dc-* plenv build with a thread variant", 1 unless $v;
    my ($out, $exit)
      = run_all_versions("-version", $v, qw( --build --force --dry_run ));
    is $exit, 0, "a successful dry-run build exits 0";
  }
}

sub main () {
  test_missing_version_fails;
  test_list_still_exits_zero;
  test_build_with_nothing_to_do_exits_zero;
  test_build_failure_exits_nonzero;
  test_build_success_exits_zero;
  done_testing;
}

main

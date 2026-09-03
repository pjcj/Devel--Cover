#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# When blib exists the run is a distribution test, so the conventional
# directories holding code that is not under test are ignored by default:
# t/, test.pl, bundled build helpers in inc/ and the build system's own
# scripts.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Cwd        qw( getcwd );
use File::Spec ();
use File::Temp qw( tempdir );

use Test::More import => [qw( diag done_testing is ok )];

my $Tmpdir = File::Spec->rel2abs(tempdir(CLEANUP => 1));
my $Root   = getcwd;
my $N      = 0;

sub run_covered ($dir) {
  local $ENV{DEVEL_COVER_OPTIONS};
  local $ENV{DEVEL_COVER_SELF};
  local $ENV{DEVEL_COVER_DEBUG};
  delete @ENV{qw( DEVEL_COVER_OPTIONS DEVEL_COVER_SELF DEVEL_COVER_DEBUG )};

  my $db   = File::Spec->catdir($Tmpdir, "db" . $N++);
  my $lib  = File::Spec->catdir($Root,   "blib", "lib");
  my $arch = File::Spec->catdir($Root,   "blib", "arch");
  chdir $dir or die "Can't chdir $dir: $!";
  my $cmd
    = "$^X -I$lib -I$arch"
    . " -MDevel::Cover=-db,$db,-merge,0,-summary,0,-silent,0"
    . " -e 1 2>&1";
  my $out = scalar `$cmd`;
  chdir $Root or die "Can't chdir $Root: $!";
  $out
}

sub ignores ($out) {
  my ($body) = $out =~ /^Ignoring packages matching:\n((?:[ ]{4}.*\n)*)/m;
  [map s/^[ ]{4}//r, split /\n/, $body // ""]
}

sub test_blib_ignores_inc () {
  my $ignore = ignores(run_covered($Root));
  ok grep($_ eq "^inc/", @$ignore), "a blib run ignores bundled inc/ files";
}

sub test_blib_ignores_build_scripts () {
  my $ignore = ignores(run_covered($Root));
  for my $pattern ('^Build$', '^Build\\.PL$', '^Makefile\\.PL$', "^_build/") {
    ok grep($_ eq $pattern, @$ignore), "a blib run ignores $pattern";
  }
}

sub test_no_blib_keeps_inc () {
  my $dir = File::Spec->catdir($Tmpdir, "nolib");
  mkdir $dir or die "Can't mkdir $dir: $!";
  my $ignore = ignores(run_covered($dir));
  is grep($_ eq "^inc/", @$ignore), 0,
    "without blib, inc/ files are not ignored";
}

sub main () {
  test_blib_ignores_inc;
  test_blib_ignores_build_scripts;
  test_no_blib_keeps_inc;
  done_testing;
}

main;

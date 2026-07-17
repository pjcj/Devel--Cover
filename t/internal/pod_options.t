#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# _parse_pod_options classifies the dash-separated tokens of a
# -coverage,pod-... option into keys and values.  A value whose text merely
# contains a key name (helper_private contains private) must stay a value,
# not open a new key and orphan the user's pattern.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use File::Path qw( make_path );
use File::Spec ();
use File::Temp qw( tempdir );

use Test::More import => [qw( diag done_testing is plan )];
use Devel::Cover::Test::Showcase qw( run_cover );

eval "require Pod::Coverage; 1" or do {
  plan skip_all => "Pod::Coverage not available";
  exit;
};

my $Tmpdir = File::Spec->rel2abs(tempdir(CLEANUP => 1));

sub write_module () {
  my $libdir = File::Spec->catdir($Tmpdir, "lib");
  make_path($libdir);
  my $path = File::Spec->catfile($libdir, "PodOpt.pm");
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print {$fh} <<'PERL' =~ s/^  //gmr;
  package PodOpt;
  use strict;
  use warnings;

  sub visible        { 1 }
  sub helper_private { 2 }

  1;

  __END__

  =head2 visible

  A documented sub.

  =cut
PERL
  close $fh or die "Cannot close $path: $!";
  $libdir
}

sub create_db ($libdir) {
  my $db     = File::Spec->catdir($Tmpdir, "cover_db");
  my $select = quotemeta File::Spec->catfile($libdir, "PodOpt.pm");
  $select =~ s|\\|\\\\|g if $^O eq "MSWin32";

  local $ENV{DEVEL_COVER_SELF};
  local $ENV{DEVEL_COVER_OPTIONS};
  delete @ENV{qw( DEVEL_COVER_SELF DEVEL_COVER_OPTIONS )};

  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$libdir"
    . " -MDevel::Cover=-db,$db,-silent,1,-merge,0,-select,$select"
    . ",-coverage,pod-also_private-helper_private"
    . ' -e "use PodOpt; PodOpt::visible(); PodOpt::helper_private()"' . " 2>&1";
  my $out = `$cmd`;
  die "Failed to create cover_db:\n$out\n" if $?;
  $db
}

sub test_also_private_value_is_kept () {
  my $libdir = write_module;
  my $db     = create_db($libdir);

  my ($out, $exit) = run_cover("--report", "text", "--silent", $db);
  is $exit, 0, "cover --report text exits 0" or diag $out;

  my ($pod) = $out =~ /PodOpt\.pm\s+([\d.]+)/;
  is $pod, "100.0", "helper_private is excused by the also_private pattern"
    or diag $out;
}

sub main () {
  test_also_private_value_is_kept;
  done_testing;
}

main;

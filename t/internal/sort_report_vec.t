#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# The run database stores per-criterion bit vectors recording whether each
# branch/condition leg was ever exercised.  add_branch_cover and
# add_condition_cover must store a boolean, not the raw count truncated to
# one bit.  The sort report is the consumer of this data.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use File::Spec ();
use File::Temp qw( tempdir );

use Test::More import => [qw( diag done_testing is ok )];
use Devel::Cover::Test::Showcase qw( run_cover );

my $Tmpdir = File::Spec->rel2abs(tempdir(CLEANUP => 1));

sub write_script () {
  my $path = File::Spec->catfile($Tmpdir, "legs.pl");
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print {$fh} <<'PERL' =~ s/^  //gmr;
  use strict;
  use warnings;

  my $y;
  for my $i (0, 1, 0, 1) {
    if ($i) { $y = "a" } else { $y = "b" }
    my $r = $i || 0;
  }
PERL
  close $fh or die "Cannot close $path: $!";
  $path
}

sub create_db ($script) {
  my $db     = File::Spec->catdir($Tmpdir, "cover_db");
  my $select = quotemeta $script;
  $select =~ s|\\|\\\\|g if $^O eq "MSWin32";

  local $ENV{DEVEL_COVER_SELF};
  local $ENV{DEVEL_COVER_OPTIONS};
  delete @ENV{qw( DEVEL_COVER_SELF DEVEL_COVER_OPTIONS )};

  my $cmd
    = "$^X -Iblib/lib -Iblib/arch"
    . " -MDevel::Cover=-db,$db,-silent,1,-merge,0,-select,$select"
    . ",-coverage,branch,condition $script 2>&1";
  my $out = `$cmd`;
  die "Failed to create cover_db:\n$out\n" if $?;
  $db
}

sub test_vec_bits_are_boolean () {
  my $script = write_script;
  my $db     = create_db($script);

  my ($out, $exit) = run_cover("--report", "sort", "--silent", $db);
  is $exit, 0, "cover --report sort exits 0" or diag $out;

  my @legs = $out =~ /(?:branch|condition)\s+(\d+): ([01]+)\n/g;
  ok @legs >= 4, "branch and condition entries reported" or diag $out;
  while (my ($size, $bits) = splice @legs, 0, 2) {
    is $bits, "1" x $size, "legs executed twice record bit 1";
  }

  my ($count, $total) = $out =~ m|Count:\s+(\d+) / (\d+)|;
  ok $total, "sort report prints a vec count" or diag $out;
  is $count, $total, "every recorded leg counts as covered";
}

sub main () {
  test_vec_bits_are_boolean;
  done_testing;
}

main;

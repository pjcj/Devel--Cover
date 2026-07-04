#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# When golden results are regenerated, a per-version golden file must be
# pruned if it merely duplicates the golden the test system would otherwise
# fall back to (the highest existing version below the current $]). The pruning
# must compare against that earlier version even when a golden for the exact
# current version already exists.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is ok )];

use Devel::Cover::Test ();

## no critic (Subroutines::ProtectPrivateSubs)

my $Below   = "5.008000";
my $Below2  = "5.010000";
my $Current = "$]";
my $Later   = "5.099000";

sub write_gold ($dir, $test, $version, $content = "") {
  my $path = "$dir/$test.$version";
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
  $path
}

is Devel::Cover::Test::_previous_gold_version(tempdir(CLEANUP => 1), "t"),
  "5.0", "no goldens gives 5.0";

{
  my $dir = tempdir(CLEANUP => 1);
  write_gold($dir, "t", $Current);
  write_gold($dir, "t", $Later);
  is Devel::Cover::Test::_previous_gold_version($dir, "t"), "5.0",
    "only current and later versions gives 5.0";
}

{
  my $dir = tempdir(CLEANUP => 1);
  write_gold($dir, "t", $Below);
  write_gold($dir, "t", $Below2);
  write_gold($dir, "t", $Current);
  write_gold($dir, "t", $Later);
  is Devel::Cover::Test::_previous_gold_version($dir, "t"), $Below2,
    "highest version below current, ignoring current and later";
}

my $Tester = Devel::Cover::Test->new("dummy");

{
  my $dir = tempdir(CLEANUP => 1);
  write_gold($dir, "g", $Below, "SAME\n");
  my $new = write_gold($dir, "g", $Current, "SAME\n");
  $Tester->_prune_redundant_gold($dir, "g", $new, "SAME\n");
  ok !-e $new, "redundant current-version golden deleted";
}

{
  my $dir = tempdir(CLEANUP => 1);
  write_gold($dir, "g", $Below, "OLD\n");
  my $new = write_gold($dir, "g", $Current, "NEW\n");
  $Tester->_prune_redundant_gold($dir, "g", $new, "NEW\n");
  ok -e $new, "differing current-version golden kept";
}

{
  my $dir = tempdir(CLEANUP => 1);
  my $new = write_gold($dir, "g", $Current, "BASE\n");
  $Tester->_prune_redundant_gold($dir, "g", $new, "BASE\n");
  ok -e $new, "baseline golden with no earlier version kept";
}

done_testing;

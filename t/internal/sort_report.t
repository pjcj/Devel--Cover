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

use File::Spec ();
use File::Temp qw( tempdir );

use Test::More import => [qw( done_testing like ok )];

use Devel::Cover::DB           ();
use Devel::Cover::Report::Sort ();

my $Tmpdir = File::Spec->rel2abs(tempdir(CLEANUP => 1));

sub covered_db ($label) {
  my $dir = File::Spec->catdir($Tmpdir, $label);
  mkdir $dir or die "Cannot create $dir: $!";
  my $script = File::Spec->catfile($dir, "run.pl");
  open my $fh, ">", $script or die "Cannot write $script: $!";
  print $fh "my \$x = 0;\n\$x++ for 1 .. 3;\n";
  close $fh or die "Cannot close $script: $!";

  my $db = File::Spec->catdir($dir, "cover_db");
  local $ENV{DEVEL_COVER_SELF};
  local $ENV{DEVEL_COVER_OPTIONS};
  delete @ENV{qw( DEVEL_COVER_SELF DEVEL_COVER_OPTIONS )};
  system(
    $^X, "-Iblib/lib", "-Iblib/arch",
    "-MDevel::Cover=-db,$db,-silent,1,-merge,0", $script,
  ) == 0 or die "Failed to run $label under Devel::Cover: $?";
  $db
}

sub sort_output ($db_path) {
  my $db      = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  my @files   = $db->cover->items;
  my $options = { coverage => ["statement"], file => \@files };

  my $output;
  {
    open my $fh, ">", \$output or die "Cannot open scalar ref: $!";
    local *STDOUT = $fh;
    Devel::Cover::Report::Sort->report($db, $options);
    close $fh or die "Cannot close scalar ref: $!";
  }
  ($output // "", $db)
}

sub test_run_times_are_epoch_seconds () {
  my ($output, $db) = sort_output(covered_db("times"));
  my @runs = $db->runs;
  ok @runs, "database contains at least one run";
  for my $r (@runs) {
    my $start  = scalar gmtime $r->start;
    my $finish = scalar gmtime $r->finish;
    like $output, qr/^Start:\s+\Q$start\E$/m,
      "start printed as epoch seconds ($start)";
    like $output, qr/^Finish:\s+\Q$finish\E$/m,
      "finish printed as epoch seconds ($finish)";
  }
}

sub main () {
  test_run_times_are_epoch_seconds;
  done_testing;
}

main;

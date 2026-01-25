#!/usr/bin/perl

use 5.20.0;
use warnings;

use feature qw( signatures );
no warnings qw( experimental::signatures );

use Test::More import => [qw( done_testing is like ok )];

use File::Basename qw( dirname );
use File::Copy     qw( copy );
use File::Spec     ();
use File::Temp     qw( tempdir );

my $Test_dir = dirname(__FILE__);
my $Root     = File::Spec->catdir($Test_dir, "..", "..");
my $Bin      = File::Spec->catfile($Root, "bin", "gcov2perl");
my $Fixtures = File::Spec->catdir($Root, "t", "fixtures", "gcov2perl");

sub setup () {
  my $tmpdir = tempdir(CLEANUP => 1);

  copy(File::Spec->catfile($Fixtures, "simple.c"), $tmpdir)
    or die "Failed to copy simple.c: $!";
  copy(
    File::Spec->catfile($Fixtures, "simple.c.gcov.fixture"),
    File::Spec->catfile($tmpdir,   "simple.c.gcov")
  ) or die "Failed to copy simple.c.gcov.fixture: $!";

  $tmpdir
}

sub test_gcov2perl ($tmpdir) {

  my $gcov_file = File::Spec->catfile($tmpdir, "simple.c.gcov");
  my $db_dir    = File::Spec->catdir($tmpdir, "cover_db");
  my $cmd       = "$^X -Iblib/lib $Bin -db $db_dir $gcov_file 2>&1";
  my $output    = `$cmd`;
  my $exit_code = $? >> 8;

  is $exit_code, 0, "gcov2perl exits successfully";
  like $output, qr/Writing coverage database/,
    "gcov2perl reports writing database";
  ok -d $db_dir, "coverage database directory created";
  ok -d File::Spec->catdir($db_dir, "runs"), "runs directory created";

  opendir my $dh, File::Spec->catdir($db_dir, "runs")
    or die "Cannot open runs directory: $!";
  my @runs = grep { !/^\./ } readdir $dh;
  closedir $dh;

  is @runs, 1, "one run directory created";
}

sub main () {
  my $tmpdir = setup;
  test_gcov2perl($tmpdir);
  done_testing;
}

main;

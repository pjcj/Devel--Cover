#!/usr/bin/perl

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Test::More import => [qw( diag done_testing is like ok unlike )];

use Config         qw( %Config );
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

  copy(
    File::Spec->catfile($Fixtures, "simple.c.fixture"),
    File::Spec->catfile($tmpdir,   "simple.c"),
  ) or die "Failed to copy simple.c.fixture: $!";
  copy(
    File::Spec->catfile($Fixtures, "simple.c.gcov.fixture"),
    File::Spec->catfile($tmpdir,   "simple.c.gcov"),
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

sub make_core_gcov ($tmpdir, $source) {
  my $gcov_path = File::Spec->catfile($tmpdir, "core_header.h.gcov");
  open my $fh, ">", $gcov_path or die "Cannot create $gcov_path: $!";
  print $fh "        -:    0:Source:$source\n";
  print $fh "        -:    0:Graph:core_header.gcno\n";
  print $fh "        -:    0:Data:core_header.gcda\n";
  print $fh "        -:    0:Runs:1\n";
  print $fh "        1:    1:/* dummy executed line */\n";
  close $fh or die "Cannot close $gcov_path: $!";
  $gcov_path;
}

sub run_gcov2perl ($db_dir, $gcov_path, @extra) {
  my $cmd = join " ", $^X, "-Iblib/lib", $Bin, "-db", $db_dir, @extra,
    $gcov_path, "2>&1";
  my $output    = `$cmd`;
  my $exit_code = $? >> 8;
  ($exit_code, $output);
}

sub test_skip_core ($tmpdir) {
  my $core_dir    = File::Spec->catdir($Config{archlibexp}, "CORE");
  my $core_source = File::Spec->catfile($core_dir, "perl.h");

  unless (-f $core_source) {
    diag "no $core_source - skipping CORE-skip tests";
    return;
  }

  my $gcov_path = make_core_gcov($tmpdir, $core_source);

  my $db_dir = File::Spec->catdir($tmpdir, "cover_db_core_default");
  my ($exit_code, $output) = run_gcov2perl($db_dir, $gcov_path);
  is $exit_code, 0, "gcov2perl exits successfully when given CORE source";
  unlike $output, qr/Writing coverage database/,
    "gcov2perl does not write database for CORE source by default";
  ok !-d File::Spec->catdir($db_dir, "runs"),
    "no runs directory created for CORE source by default";

  my $db_dir_no = File::Spec->catdir($tmpdir, "cover_db_core_no_skip");
  my ($exit_no, $output_no)
    = run_gcov2perl($db_dir_no, $gcov_path, "-no-skip-core");
  is $exit_no, 0, "gcov2perl exits successfully with -no-skip-core";
  like $output_no, qr/Writing coverage database/,
    "gcov2perl writes database for CORE source with -no-skip-core";
  ok -d File::Spec->catdir($db_dir_no, "runs"),
    "runs directory created for CORE source with -no-skip-core";
}

sub main () {
  my $tmpdir = setup;
  test_gcov2perl($tmpdir);
  test_skip_core($tmpdir);
  done_testing;
}

main;

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

use File::Path qw( make_path );
use File::Spec ();
use File::Temp qw( tempdir );

use Test::More import => [qw( done_testing is plan )];

BEGIN {
  plan skip_all => "JSON::MaybeXS required for this test"
    unless eval "require JSON::MaybeXS; 1";
  plan skip_all => "CPAN::Meta required for this test"
    unless eval "require CPAN::Meta; 1";
}

my $Tmpdir = File::Spec->rel2abs(tempdir(CLEANUP => 1));

sub write_file ($path, $contents) {
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $contents;
  close $fh or die "Cannot close $path: $!";
}

sub run_in ($name, $meta = undef) {
  my $dir = File::Spec->catdir($Tmpdir, $name);
  make_path($dir);
  write_file(File::Spec->catfile($dir, "MYMETA.json"), $meta) if $meta;
  my $script = File::Spec->catfile($dir, "run.pl");
  write_file($script, "my \$x = 0;\n\$x++ for 1 .. 3;\n");

  my $db = File::Spec->catdir($dir, "cover_db");
  local $ENV{DEVEL_COVER_SELF};
  local $ENV{DEVEL_COVER_OPTIONS};
  local $ENV{DEVEL_COVER_DB_FORMAT} = "JSON";
  delete @ENV{qw( DEVEL_COVER_SELF DEVEL_COVER_OPTIONS )};
  system(
    $^X, "-Iblib/lib", "-Iblib/arch",
    "-MDevel::Cover=-db,$db,-dir,$dir,-silent,1,-merge,0", $script,
  ) == 0 or die "Failed to run under Devel::Cover: $?";

  my ($file) = grep !/\.lock$/,
    glob File::Spec->catfile($db, "runs", "*", "cover.*");
  open my $fh, "<", $file or die "Cannot read $file: $!";
  my $json = do { local $/; <$fh> };
  close $fh or die "Cannot close $file: $!";
  my ($run) = values JSON::MaybeXS::decode_json($json)->{runs}->%*;
  ($run, $dir)
}

sub test_directory_without_mymeta () {
  my ($run, $dir) = run_in("myapp");
  is $run->{name},    $dir,      "run name defaults to the run directory";
  is $run->{version}, "unknown", "run version defaults to unknown";
}

sub test_directory_with_mymeta () {
  my ($run) = run_in("metaapp", <<'JSON');
{
   "abstract" : "test distribution",
   "author" : [ "nobody" ],
   "dynamic_config" : 0,
   "generated_by" : "Devel::Cover tests",
   "license" : [ "perl_5" ],
   "meta-spec" : { "version" : 2 },
   "name" : "Test-Dist",
   "release_status" : "stable",
   "version" : "0.01"
}
JSON
  is $run->{name},    "Test-Dist", "run name comes from MYMETA.json";
  is $run->{version}, "0.01",      "run version comes from MYMETA.json";
}

sub main () {
  test_directory_without_mymeta;
  test_directory_with_mymeta;
  done_testing;
}

main;

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Cwd        qw( getcwd );
use File::Spec ();
use File::Temp qw( tempdir );

use Test::More import => [qw( done_testing is isnt like note plan unlike )];

my $Project   = getcwd;
my $Cover     = File::Spec->catfile($Project, "bin", "cover");
my $Blib_lib  = File::Spec->catdir($Project, "blib", "lib");
my $Blib_arch = File::Spec->catdir($Project, "blib", "arch");

unless (-f $Cover && -d $Blib_lib && -d $Blib_arch) {
  plan skip_all => "build artefacts missing - run after `make`";
  exit;
}

my $Tmpdir = tempdir(CLEANUP => 1);
my $Db     = File::Spec->catdir($Tmpdir, "cover_db");

sub build_db () {
  my $script = File::Spec->catfile($Tmpdir, "covered.pl");
  open my $fh, ">", $script or die "open $script: $!";
  print {$fh} "my \$x = 0;\n\$x++ for 1 .. 3;\n";
  close $fh or die "close $script: $!";

  my @cmd = (
    $^X, "-I$Blib_lib", "-I$Blib_arch", "-MDevel::Cover=-db,$Db,-silent",
    $script,
  );
  system(@cmd) == 0 or die "failed to build test db";
}

sub run_cover (@args) {
  my $cmd = join " ", $^X, $Cover, @args, $Db, "2>&1";
  my $out = `$cmd`;
  note $out;
  ($? >> 8, $out)
}

sub test_report_annotation_combination () {
  my ($rc, $out) = run_cover(
    "-silent", "-report", "json", "-outputfile",
    File::Spec->catfile($Tmpdir, "out.json"),
    "-annotation", "random", "-count", 3,
  );
  is $rc, 0, "report and annotation option sets don't collide";
  unlike $out, qr/Unknown option|Bad option|Invalid command line options/,
    "no option-parsing error emitted";
}

sub test_unknown_option_rejected () {
  my ($rc, $out)
    = run_cover("-silent", "-report", "text", "-definitely_not_an_option");
  isnt $rc, 0, "unknown option still fails";
  like $out, qr/Unknown option/, "unknown option reported clearly";
}

sub main () {
  local $ENV{PERL5LIB} = join ":", $Blib_lib, $Blib_arch,
    ($ENV{PERL5LIB} // ());

  build_db;
  test_report_annotation_combination;
  test_unknown_option_rejected;
  done_testing;
}

main;

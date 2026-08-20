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

use Test::More import => [qw( diag done_testing is like )];
use Devel::Cover::Test::Showcase qw( create_cover_db run_cover setup_lib_dir );

my ($Tmpdir, $Libdir) = setup_lib_dir;
my $Cover_db = create_cover_db($Tmpdir, $Libdir);

sub test_invalid_report_alone () {
  my ($out, $exit)
    = run_cover("--report", "bogus", "--silent", "--nosummary", $Cover_db);
  is $exit, 1, "an unloadable report exits 1";
  like $out, qr/not a recognised output format/, "the failure is reported";
}

sub test_invalid_report_beside_a_good_one () {
  my ($out, $exit) = run_cover(
    "--report", "bogus",       "--report",    "text",
    "--silent", "--nosummary", "--outputdir", "$Tmpdir/masked",
    $Cover_db,
  );
  is $exit, 1, "a working report does not mask an unloadable one";
  like $out, qr/not a recognised output format/, "the failure is reported";
}

sub test_valid_reports_still_pass () {
  my ($out, $exit) = run_cover(
    "--report",    "text",         "--silent", "--nosummary",
    "--outputdir", "$Tmpdir/good", $Cover_db,
  );
  is $exit, 0, "a working report still exits 0" or diag $out;
}

sub main () {
  test_invalid_report_alone;
  test_invalid_report_beside_a_good_one;
  test_valid_reports_still_pass;
  done_testing;
}

main;

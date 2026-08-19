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

use List::Util qw( sum );
use Test::More import => [qw( diag done_testing is ok )];
use Devel::Cover::Test::Showcase qw(
  create_cover_db
  run_cover
  setup_lib_dir
);

sub text_report ($libdir, $cover_db, @extra) {
  my ($out, $exit) = run_cover(
    "--select", "$libdir/Covered/Trivial.pm",
    "--select", "$libdir/Covered/Utils.pm",
    "--report", "text",
    "--silent", @extra,
    $cover_db,
  );
  is $exit, 0, "cover --report text exits 0 (@extra)" or diag $out;
  $out
}

sub module_summary ($out) {
  my ($table) = $out =~ /(Module Summary\n-+\n\n.*?\n\n)/s;
  $table
}

sub module_cc ($table) {
  my ($cc) = $table =~ /^\s*\d+\s+(\d+)\s/m;
  $cc
}

sub file_ccs ($out) {
  $out =~ /File Summary\n-+\n\nCC[^\n]*\n[- ]+\n\s*(\d+)\s/g
}

# The Module Summary must cover only the selected files, with or without
# -summary.  CC aggregates as sum - count + 1, so the module CC must equal
# the file CC sum minus one per extra file.
sub test_select_summary () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);

  my $plain     = text_report($libdir, $cover_db);
  my $nosummary = text_report($libdir, $cover_db, "--nosummary");

  my $table = module_summary($plain);

  ok $table, "text report has a Module Summary table";
  is module_summary($nosummary), $table,
    "-nosummary leaves the Module Summary unchanged";

  for my $run ([summary => $plain], [nosummary => $nosummary]) {
    my ($name, $out) = @$run;
    my @file_cc = file_ccs($out);
    is @file_cc, 2, "$name run has two File Summary tables";
    is module_cc(module_summary($out)), sum(@file_cc) - (@file_cc - 1),
      "$name module CC derives from the file CC values";
  }
}

sub main () {
  test_select_summary;
  done_testing;
}

main;

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

use Test::More import => [qw( diag done_testing is like unlike )];
use Devel::Cover::Test::Showcase qw(
  create_cover_db
  run_cover
  setup_lib_dir
  slurp
);

# Stored file keys must be matched as literal text, not as Lua patterns
sub test_nvim_report_literal_matching () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "nvim", "--silent", $cover_db,
  );

  is $exit, 0, "cover --report nvim exits 0" or diag $out;

  my $lua     = slurp("$cover_db/coverage.lua");
  my $pattern = 'string.find(filename, f .. "$")';
  my $literal = "string.sub(filename, -#f) == f";
  unlike $lua, qr/\Q$pattern\E/,
    "file matching does not build a Lua pattern from the path";
  like $lua, qr/\Q$literal\E/, "file matching uses a literal suffix comparison";
}

sub main () {
  test_nvim_report_literal_matching;
  done_testing;
}

main;

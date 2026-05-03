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
use Devel::Cover::Test::Showcase qw(
  create_cover_db
  run_cover
  setup_lib_dir
);

# The compilation reporter emits one line per uncovered location in a format
# similar to Perl's own compilation errors, so editors with a quickfix-style
# error navigator can step through them.
sub test_compilation_report () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "compilation",
    "--silent",     $cover_db,
  );

  is $exit, 0, "cover --report compilation exits 0" or diag $out;

  like $out, qr/Uncovered statement at .* line \d+/,
    "uncovered statement line emitted";
  like $out, qr/Uncovered subroutine \S+ at .* line \d+/,
    "uncovered subroutine line emitted";
  like $out, qr|Uncovered MC/DC pair \([^)]*\) at .* line \d+: .+|,
    "uncovered MC/DC pair line emitted";
}

sub main () {
  test_compilation_report;
  done_testing;
}

main;

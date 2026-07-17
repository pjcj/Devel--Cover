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

use Test::More import => [qw( diag done_testing is like ok unlike )];
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

# The template's sign_priority default and the POD's documented one must agree
sub test_sign_priority_default_documented () {
  require Devel::Cover::Report::Nvim;
  my $src = slurp($INC{"Devel/Cover/Report/Nvim.pm"});
  my ($code_default)
    = $src =~ /sign_priority = vim\.g\.devel_cover_sign_priority or (\d+),/;
  my ($pod_default)
    = $src =~ /devel_cover_sign_priority -- Sign priority \(default: (\d+)\)/;
  ok defined $code_default, "template sign_priority default found";
  ok defined $pod_default,  "POD sign_priority default found";
  is $pod_default, $code_default, "POD documents the template default";
}

sub main () {
  test_nvim_report_literal_matching;
  test_sign_priority_default_documented;
  done_testing;
}

main;

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

use Test::More import => [qw( diag done_testing is like plan unlike )];
use Devel::Cover::Test::Showcase qw(
  create_cover_db
  run_cover
  setup_lib_dir
  slurp
);

eval "require Template; 1" or do {
  plan skip_all => "Template not available";
  exit;
};

# Stored file keys must be matched as literal text, not as Vim regexes
sub test_vim_report_literal_matching () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "vim", "--silent", $cover_db,
  );

  is $exit, 0, "cover --report vim exits 0" or diag $out;

  my $vim     = slurp("$cover_db/coverage.vim");
  my $regex   = 'match(a:filename, s:f . "$")';
  my $literal = q[match(a:filename, '\V' . escape(s:f, '\') . '\$')];
  unlike $vim, qr/\Q$regex\E/,
    "file matching does not build a regex from the raw path";
  like $vim, qr/\Q$literal\E/,
    "file matching uses a very-nomagic literal pattern";
}

sub main () {
  test_vim_report_literal_matching;
  done_testing;
}

main;

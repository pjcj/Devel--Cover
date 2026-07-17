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

use Test::More import => [qw( diag done_testing is is_deeply ok plan )];
use Devel::Cover::DB             ();
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

sub types_from_vim_report ($cover_db, $libdir, $seed) {
  local $ENV{PERL_HASH_SEED}    = $seed;
  local $ENV{PERL_PERTURB_KEYS} = "0";
  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "vim", "--silent", $cover_db,
  );
  is $exit, 0, "cover --report vim exits 0 (seed $seed)" or diag $out;
  my $vim = slurp("$cover_db/coverage.vim");
  my ($list) = $vim =~ /^let s:types = \[(.*?)\]/ms;
  ok defined $list, "types list found in coverage.vim (seed $seed)";
  [grep !/_error$/, ($list // "") =~ /"(\w+)"/g]
}

# Criteria must come out in canonical order, identical under any hash seed
sub test_editor_types_order () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);

  my $t0 = types_from_vim_report($cover_db, $libdir, "0x0");
  my $t1 = types_from_vim_report($cover_db, $libdir, "0x1");

  my %seen      = map { $_ => 1 } @$t0;
  my @canonical = grep $_ ne "time", @Devel::Cover::DB::Criteria;
  my @expected  = grep $seen{$_}, @canonical;

  ok @expected >= 4, "several criteria collected" or diag "@expected";
  is_deeply $t0, \@expected, "types in canonical order (seed 0x0)";
  is_deeply $t1, \@expected, "types in canonical order (seed 0x1)";
  ok !$seen{time} && !$seen{total}, "time and total are excluded";
}

sub main () {
  test_editor_types_order;
  done_testing;
}

main;

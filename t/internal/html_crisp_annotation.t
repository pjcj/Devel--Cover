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

use File::Spec ();
use Test::More import => [qw( done_testing is like ok unlike )];
use Devel::Cover::Test::Showcase qw(
  create_cover_db
  run_cover
  setup_lib_dir
  slurp
);

my ($Tmpdir, $Libdir, $Cover_db);

sub file_pages ($outdir) {
  map slurp($_), grep !m|/coverage\.html$|, glob "$outdir/*.html"
}

sub test_annotation_columns () {
  my $outdir = File::Spec->catdir($Tmpdir, "html_ann");
  my ($out, $exit) = run_cover(
    "--select_dir", $Libdir, "--report",     "html_crisp",
    "--outputdir",  $outdir, "--annotation", "random",
    "-count",       2,       "--silent",     $Cover_db,
  );
  is $exit, 0, "cover succeeds with -annotation random";

  my @pages = file_pages($outdir);
  ok @pages, "file pages generated";
  for my $i (0 .. $#pages) {
    my $page = $pages[$i];
    like $page, qr|<th class="ann-h">rnd0</th><th class="ann-h">rnd1</th>|,
      "page $i has the annotation header row";
    like $page, qr|<td role="cell" class="ann[^"]*">\d</td>|,
      "page $i has annotation cells";
    like $page, qr|<tr class="line-detail"><td colspan="6">|,
      "page $i detail rows span the annotation columns"
      if $page =~ /line-detail/;
  }
  is grep(/line-detail/, @pages) > 0, 1, "some pages have detail rows";
}

sub test_no_annotation () {
  my $outdir = File::Spec->catdir($Tmpdir, "html_plain");
  my ($out, $exit) = run_cover(
    "--select_dir", $Libdir, "--report", "html_crisp",
    "--outputdir",  $outdir, "--silent", $Cover_db,
  );
  is $exit, 0, "cover succeeds without -annotation";

  my @pages = file_pages($outdir);
  ok @pages, "file pages generated";
  for my $i (0 .. $#pages) {
    my $page = $pages[$i];
    unlike $page, qr|class="ann|, "page $i has no annotation markup";
    like $page, qr|<tr class="line-detail"><td colspan="4">|,
      "page $i detail rows keep their width"
      if $page =~ /line-detail/;
  }
}

sub main () {
  ($Tmpdir, $Libdir) = setup_lib_dir;
  $Cover_db = create_cover_db($Tmpdir, $Libdir);

  test_annotation_columns;
  test_no_annotation;
}

main;
done_testing;

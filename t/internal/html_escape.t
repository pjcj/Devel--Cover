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

use Cwd        qw( realpath );
use File::Path qw( make_path );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing is like plan unlike )];
use Devel::Cover::Test::Showcase qw( run_cover slurp );

eval "require HTML::Entities; 1" or do {
  plan skip_all => "HTML::Entities not available";
  exit;
};

my $Have_template = eval "require Template; 1";

my $Fixture = <<'PERL';
package Fixture;
use strict;
use warnings;

sub decide {
  my ($a, $b) = @_;
  my $r = ($a < 3 && $b) ? "<script>xss</script>" : "ok";
  return $r;
}

1;
PERL

# When no syntax highlighter runs (none installed, or both disabled), the
# raw source and coverage text fall back to the page unhighlighted; they
# must be entity-escaped, not emitted raw.
sub _setup () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $libdir = File::Spec->catdir($tmpdir, "lib");
  make_path($libdir);

  my $path = File::Spec->catfile($libdir, "Fixture.pm");
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $Fixture;
  close $fh or die "Cannot close $path: $!";

  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$libdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0"
    . ' -e "use Fixture; my @r = (Fixture::decide(1, 1),'
    . ' Fixture::decide(5, 0))" 2>&1';
  my $out = `$cmd`;
  die "Failed to create cover_db:\n$out\n" if $?;

  ($tmpdir, $cover_db)
}

sub _report ($tmpdir, $cover_db, $report) {
  my $outdir = File::Spec->catdir($tmpdir, $report);
  my ($out, $exit) = run_cover(
    "--report", $report,      "--outputdir", $outdir,
    "--silent", "-noppihtml", "-noperltidy", $cover_db,
  );
  is $exit, 0, "cover --report $report exits 0" or diag $out;
  $outdir
}

sub test_html_basic ($tmpdir, $cover_db) {
  my $outdir = _report($tmpdir, $cover_db, "html_basic");

  my ($file_page) = grep !m|/coverage\.html$| && !/--\w+\.html$/,
    glob "$outdir/*.html";
  my $html = slurp($file_page);
  unlike $html, qr|<script>xss|, "html_basic: file page escapes raw source";
  like $html, qr|&lt;script&gt;xss|,
    "html_basic: file page contains escaped source";

  for my $section (qw( branch condition mcdc )) {
    my ($page) = glob "$outdir/*--$section.html";
    my $section_html = slurp($page);
    like $section_html, qr/&lt; 3 (?:&amp;&amp;|and)/,
      "html_basic: $section text is escaped, not empty or raw";
    unlike $section_html, qr|\$a < 3|, "html_basic: $section text is not raw";
  }
}

sub test_html_crisp ($tmpdir, $cover_db) {
  my $outdir      = _report($tmpdir, $cover_db, "html_crisp");
  my ($file_page) = grep !m|/coverage\.html$|, glob "$outdir/*.html";
  my $html        = slurp($file_page);
  unlike $html, qr|<script>xss|, "html_crisp: file page escapes raw source";
  like $html, qr|&lt;script&gt;xss|,
    "html_crisp: file page contains escaped source";
}

sub main () {
  my ($tmpdir, $cover_db) = _setup;
  test_html_basic($tmpdir, $cover_db) if $Have_template;
  test_html_crisp($tmpdir, $cover_db);
  done_testing;
}

main;

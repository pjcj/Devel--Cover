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

sub left_always_true {
  my ($b) = @_;
  my $always = 1;
  # uncoverable mcdc pair:1
  return $always && $b;
}

1;
PERL

# An excused atomic must not render as a plain uncovered pill: it carries a
# "-" prefix (matching the text reporters) and the satisfied colour class, so
# the pills agree with the decision row's excused-as-covered state.
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
    . ' -e "use Fixture; my @r = (Fixture::left_always_true(1),'
    . ' Fixture::left_always_true(0))" 2>&1';
  my $out = `$cmd`;
  die "Failed to create cover_db:\n$out\n" if $?;

  ($tmpdir, $cover_db)
}

sub _report ($tmpdir, $cover_db, $report) {
  my $outdir = File::Spec->catdir($tmpdir, $report);
  my ($out, $exit) = run_cover(
    "--report", $report, "--outputdir", $outdir, "--silent", $cover_db,
  );
  is $exit, 0, "cover --report $report exits 0" or diag $out;
  my ($mcdc_page) = glob "$outdir/*--mcdc.html";
  ($outdir, $mcdc_page)
}

sub test_html_minimal ($tmpdir, $cover_db) {
  my (undef, $page) = _report($tmpdir, $cover_db, "html_minimal");
  my $html = slurp($page);
  like $html, qr|<span class="c3">-\$always</span>|,
    "html_minimal: excused pill has - prefix and covered class";
  like $html, qr|<span class="c3">\$b</span>|,
    "html_minimal: covered pill unchanged";
  unlike $html, qr|<span class="c0">|, "html_minimal: no uncovered pill";
}

sub test_html_basic ($tmpdir, $cover_db) {
  my (undef, $page) = _report($tmpdir, $cover_db, "html_basic");
  my $html = slurp($page);
  like $html, qr|class="c3">\s*-\$always\s*</span>|,
    "html_basic: excused pill has - prefix and covered class";
  like $html, qr|class="c3">\s*\$b\s*</span>|,
    "html_basic: covered pill unchanged";
  like $html, qr|<a name="9-1">|,
    "html_basic: row anchor matches the file-page link";
}

sub test_html_subtle ($tmpdir, $cover_db) {
  my (undef, $page) = _report($tmpdir, $cover_db, "html_subtle");
  my $html = slurp($page);
  like $html, qr|<span class="covered">-\$always</span>|,
    "html_subtle: excused pill has - prefix and covered class";
  like $html, qr|<span class="covered">\$b</span>|,
    "html_subtle: covered pill unchanged";
  unlike $html, qr|<span class="uncovered">|, "html_subtle: no uncovered pill";
}

sub test_html_crisp ($tmpdir, $cover_db) {
  my ($outdir) = _report($tmpdir, $cover_db, "html_crisp");
  my ($page)   = grep !m|/coverage\.html$|, glob "$outdir/*.html";
  my $html     = slurp($page);
  like $html, qr|mcdc-pill c3">-\$always</span>|,
    "html_crisp: excused pill has - prefix and covered class";
  like $html, qr|mcdc-pill c3">\$b</span>|,
    "html_crisp: covered pill unchanged";
  unlike $html, qr|mcdc-pill c0|, "html_crisp: no uncovered pill";
}

sub main () {
  my ($tmpdir, $cover_db) = _setup;
  test_html_minimal($tmpdir, $cover_db);
  if ($Have_template) {
    test_html_basic($tmpdir, $cover_db);
    test_html_subtle($tmpdir, $cover_db);
  }
  test_html_crisp($tmpdir, $cover_db);
  done_testing;
}

main;

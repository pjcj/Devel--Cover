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

eval "require Template; 1" or do {
  plan skip_all => "Template not available";
  exit;
};

my $Fixture = <<'PERL';
package Fixture;
use strict;
use warnings;

sub hit {
  my ($x) = @_;
  # uncoverable branch false
  if ($x) {
    return 1;
  }
  # uncoverable statement
  return 0;
}

sub cond {
  my ($x, $y) = @_;
  # uncoverable condition when:0X
  # uncoverable condition when:11
  my $r = $x && !$y;
  return $r;
}

# uncoverable subroutine
# uncoverable statement
sub never_called { 1 }

sub stale {
  # uncoverable subroutine
  # uncoverable statement
  return 42;
}

sub stale_branch {
  my ($x) = @_;
  # uncoverable branch true
  if ($x) {
    return 1;
  }
  return 0;
}

1;
PERL

my $Mixed_fixture = <<'PERL';
package Mixed;
use strict;
use warnings;

sub mixed {
  my ($x, $y) = @_;
  # uncoverable mcdc all
  my $r = $x || $y;
  return $r;
}

1;
PERL

my $Pod_fixture = <<'PERL';
package PodFix;
use strict;
use warnings;

=head1 NAME

PodFix - pod fixture

=cut

# uncoverable pod
sub undocumented { 1 }

=head2 documented

Documented sub.

=cut

# uncoverable pod
sub documented { 1 }

1;
PERL

sub _write_module ($libdir, $name, $content) {
  my $path = File::Spec->catfile($libdir, $name);
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
}

sub _collect ($tmpdir, $db_name, $coverage, $code) {
  my $libdir   = File::Spec->catdir($tmpdir, "lib");
  my $cover_db = File::Spec->catdir($tmpdir, $db_name);
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$libdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0"
    . ",-coverage,$coverage"
    . qq( -e "$code" 2>&1);
  my $out = `$cmd`;
  die "Failed to create $db_name:\n$out\n" if $?;
  $cover_db
}

sub _report ($tmpdir, $cover_db, $subdir) {
  my $outdir = File::Spec->catdir($tmpdir, $subdir);
  my ($out, $exit) = run_cover(
    "--report", "html_basic", "--outputdir", $outdir,
    "--silent", $cover_db,
  );
  is $exit, 0, "cover --report html_basic exits 0 ($subdir)" or diag $out;
  my ($page) = grep !m|/coverage\.html$| && !/--/, glob "$outdir/*.html";
  ($outdir, $page)
}

sub test_main ($tmpdir) {
  my $cover_db = _collect(
    $tmpdir,
    "cover_db",
    "statement,branch,condition,subroutine",
    "use Fixture; Fixture::hit(1); Fixture::cond(1, 1); Fixture::stale();"
      . " Fixture::stale_branch(1); Fixture::stale_branch(0)",
  );
  my ($outdir, $page) = _report($tmpdir, $cover_db, "html_basic");
  my $html = slurp($page);

  my $cx = '<td class="cx" title="marked uncoverable">';
  my $mk = '<td class="c0 mk" title="marked uncoverable but covered">';

  # File page: excused cells are striped green, stale markers striped red
  like $html, qr|\Q$cx\E\s*0\s*</td>|,
    "excused statement cell has the excused class and note";
  like $html, qr|\Q$mk\E\s*1\s*</td>|,
    "stale statement cell is red and hatched with note";
  like $html, qr|<a href="#30">|,
    "stale statement is in the uncovered link chain";
  like $html, qr|\Q$cx\E\s*<a href="[^"]*--branch\.html#8-1">\s*100|,
    "branch with excused arm has the excused class on the file page";
  like $html, qr|\Q$mk\E\s*<a href="[^"]*--branch\.html#36-1">\s*50|,
    "branch with stale marker is red and hatched on the file page";

  # Summary tooltips name the uncoverable count
  like $html, qr|title="\d+ / \d+ \(\d+ uncoverable\)"|,
    "header tooltip shows the uncoverable count";

  # Branch page: per-direction four-state rendering
  my ($branch_page) = glob "$outdir/*--branch.html";
  my $branches = slurp($branch_page);
  like $branches, qr|<td class="c3">\s*1\s*</td>\s*\Q$cx\E\s*0\s*</td>|,
    "excused branch arm has the excused class";
  like $branches, qr|\Q$mk\E\s*1\s*</td>\s*<td class="c3">\s*1\s*</td>|,
    "stale branch arm is red and hatched";
  unlike $branches, qr|<td class="c0">|, "no plain red branch arms";

  # Condition page: excused outcomes are striped green
  my ($cond_page) = glob "$outdir/*--condition.html";
  my $conds = slurp($cond_page);
  like $conds, qr|<td class="cx" title="marked uncoverable">|,
    "excused condition outcome has the excused class";
  unlike $conds, qr|<td class="c0">|, "no plain red condition outcomes";

  # Subroutine page
  my ($sub_page) = glob "$outdir/*--subroutine.html";
  my $subs = slurp($sub_page);
  like $subs, qr|\Q$cx\E\s*0\s*</td>\s*<td>\s*never_called\s*</td>|,
    "excused subroutine count cell has the excused class";
  like $subs, qr|\Q$mk\E\s*1\s*</td>\s*<td>\s*stale\s*</td>|,
    "stale subroutine count cell is red and hatched";
  like $subs, qr|<td class="c3">\s*1\s*</td>\s*<td>\s*hit\s*</td>|,
    "covered subroutine count cell unchanged";

  # The stylesheet defines the excused class and the marker hatch
  my $css = slurp("$outdir/cover.css");
  like $css, qr|\.cx \{|,                   "cover.css defines the cx class";
  like $css, qr|\.mk \{|,                   "cover.css defines the mk class";
  like $css, qr|repeating-linear-gradient|, "cover.css defines the hatch";
}

sub test_mixed ($tmpdir) {
  my $cover_db = _collect(
    $tmpdir,                    "cover_db_mixed",
    "statement,condition,mcdc", "use Mixed; Mixed::mixed(1, 0)",
  );
  my ($outdir) = _report($tmpdir, $cover_db, "html_basic_mixed");

  my ($mcdc_page) = glob "$outdir/*--mcdc.html";
  my $mcdc = slurp($mcdc_page);
  like $mcdc, qr|<td class="cx" title="marked uncoverable">\s*100\s*</td>|,
    "excused mcdc decision has the excused class";
  like $mcdc, qr|<span class="cx" title="marked uncoverable">\s*-\$x\s*</span>|,
    "excused mcdc atomic keeps the - prefix with the excused class";
  unlike $mcdc, qr|<span class="c0">|, "no red mcdc pills";
}

sub test_pod ($tmpdir) {
  my $cover_db = _collect(
    $tmpdir, "cover_db_pod", "statement,subroutine,pod",
    "use PodFix; PodFix::undocumented(); PodFix::documented()",
  );
  my ($outdir) = _report($tmpdir, $cover_db, "html_basic_pod");

  my ($sub_page) = glob "$outdir/*--subroutine.html";
  my $subs = slurp($sub_page);
  like $subs, qr|<td class="cx" title="marked uncoverable">\s*No\s*</td>|,
    "excused pod cell has the excused class";
  like $subs,
    qr|<td class="c0 mk" title="marked uncoverable but covered">\s*Yes\s*</td>|,
    "stale pod cell is red and hatched";
}

sub main () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $libdir = File::Spec->catdir($tmpdir, "lib");
  make_path($libdir);
  _write_module($libdir, "Fixture.pm", $Fixture);
  _write_module($libdir, "Mixed.pm",   $Mixed_fixture);
  _write_module($libdir, "PodFix.pm",  $Pod_fixture);

  test_main($tmpdir);
  test_mixed($tmpdir);
  test_pod($tmpdir) if eval "require Pod::Coverage; 1";
  done_testing;
}

main;

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
    "--report", "html_crisp", "--outputdir", $outdir,
    "--silent", $cover_db,
  );
  is $exit, 0, "cover --report html_crisp exits 0 ($subdir)" or diag $out;
  my ($page) = grep !m|/coverage\.html$|, glob "$outdir/*.html";
  ($outdir, $page)
}

sub test_main ($tmpdir) {
  my $cover_db = _collect(
    $tmpdir,
    "cover_db",
    "statement,branch,condition,mcdc,subroutine",
    "use Fixture; Fixture::hit(1); Fixture::cond(1, 1); Fixture::stale();"
      . " Fixture::stale_branch(1); Fixture::stale_branch(0)",
  );
  my ($outdir, $page) = _report($tmpdir, $cover_db, "html_crisp");
  my $html = slurp($page);

  # Excused statement: neutral cell, own minimap value, no red border
  like $html, qr|data-cov="3">|, "excused statement row has data-cov 3";
  my $excused_cell = '<td role="cell" class="count exec-excused" '
    . 'aria-label="marked uncoverable">0</td>';
  like $html, qr|\Q$excused_cell\E|, "excused statement count cell is neutral";

  # Stale statement marker: explicit error rendering, hatched
  my $stale_cell
    = '<td role="cell" class="count exec-0 mk" aria-label="executed 1 times, '
    . 'marked uncoverable but covered">1</td>';
  like $html, qr|\Q$stale_cell\E|,
    "stale statement count cell is red and hatched with its count";
  like $html, qr|data-cov="0"\n    class="src-c0[^"]*"|,
    "stale statement row is red in minimap and source";

  # Branch: excused arm neutral, covered arm unchanged
  like $html, qr|<td class="c3">1</td>\n<td class="cx">0</td>|,
    "excused branch arm has the excused class";

  # A marker on a construct which ran turns the whole line red
  my $stale_branch_cell = '<td role="cell" class="count exec-0 mk" '
    . 'aria-label="executed 2 times">2</td>';
  like $html, qr|\Q$stale_branch_cell\E|,
    "line with a run uncoverable branch marker is red and hatched";
  like $html, qr|<td class="c0 mk">1</td>\n<td class="c3">1</td>|,
    "the run-despite-marker arm is red and hatched in the detail";

  # A covered line carrying an excused construct is excused, not plain green
  my $excused_line_row
    = qq(data-cov="3"\n    class="has-detail">\n)
    . qq(<td role="cell" class="ln"><a id="L8" href="#L8">8</a></td>\n)
    . '<td role="cell" class="count exec-excused" '
    . 'aria-label="executed 1 times">1</td>';
  like $html, qr|\Q$excused_line_row\E|,
    "covered line with excused branch takes the excused state";

  # Subroutines: excused gets its own class and wording, stale is red
  like $html, qr|<span class="cx">never_called: not called \(uncoverable\)|,
    "excused subroutine detail is neutral with uncoverable note";
  like $html, qr|<span class="c3">hit: called|,
    "covered subroutine detail unchanged";
  like $html,
    qr|<span class="c0 mk">stale: called \(marked uncoverable but covered\)|,
    "stale subroutine detail is red and hatched with note";

  # Condition: excused outcomes neutral, summary error-based
  like $html,
    qr|<span class="summary-text c3">100%<span class="count">1/3</span></span>|,
    "condition summary percentage is error-based";
  like $html, qr|<td class="cx">0</td>|,
    "excused condition outcome has the excused class";

  # Truth tables: excused rows neutral, no red rows
  like $html,   qr|<tr class="cx">|, "excused truth table row is neutral";
  like $html,   qr|<tr class="c3">|, "covered truth table row unchanged";
  unlike $html, qr|<tr class="c0">|, "no red truth table rows";

  # Excused constructs stay out of the error filter
  my @branch_errs = $html =~ /(data-errors="[^"]*branch)/g;
  is @branch_errs, 1, "only the stale branch is in the error filter";
  my @sub_errs = $html =~ /(data-errors="[^"]*subroutine)/g;
  is @sub_errs, 1, "only the stale subroutine is in the error filter";
  unlike $html, qr|data-errors="[^"]*condition|,
    "excused condition not in error filter";

  # Summary tooltips name the uncoverable count
  like $html, qr|\(\d+ uncoverable\)|, "tooltip shows uncoverable count";

  # Help panel legend shows the four line states with live classes
  like $html, qr|<span class="legend-swatch c3"></span> covered|,
    "legend shows the covered swatch";
  like $html, qr|<span class="legend-swatch c1"></span> partial|,
    "legend shows the partial swatch";
  like $html, qr|<span class="legend-swatch c0"></span> uncovered|,
    "legend shows the uncovered swatch";
  like $html, qr|<span class="legend-swatch cx"></span> excused|,
    "legend shows the excused swatch";
  like $html, qr|<span class="legend-swatch c0 mk"></span> marked|,
    "legend shows the marked-but-ran swatch";

  # Assets know the excused state
  like slurp("$outdir/assets/style.css"), qr|--cov-excused-bg|,
    "stylesheet defines the excused colour";
  like slurp("$outdir/assets/style.css"), qr|\.legend-swatch|,
    "stylesheet sizes the legend swatches";
  like slurp("$outdir/assets/style.css"), qr|\.cx \{|,
    "stylesheet defines the cx class";
  like slurp("$outdir/assets/style.css"), qr|repeating-linear-gradient|,
    "stylesheet defines the marker hatch";
  like slurp("$outdir/assets/app.js"), qr|--cov-excused-border|,
    "minimap paints excused lines";
}

sub test_pod ($tmpdir) {
  my $cover_db = _collect(
    $tmpdir, "cover_db_pod", "statement,subroutine,pod",
    "use PodFix; PodFix::undocumented(); PodFix::documented()",
  );
  my (undef, $page) = _report($tmpdir, $cover_db, "html_crisp_pod");
  my $html = slurp($page);

  like $html, qr|class="count exec-excused"|,
    "excused pod count cell is neutral";
  like $html, qr|<span class="cx">undocumented \(uncoverable\)</span>|,
    "excused pod detail is neutral with uncoverable note";

  # A pod marker on a documented sub turns its line red
  my $stale_pod_cell = '<td role="cell" class="count exec-0 mk" '
    . 'aria-label="executed 1 times">1</td>';
  like $html, qr|\Q$stale_pod_cell\E|,
    "line with a run uncoverable pod marker is red and hatched";
  like $html,
    qr|<span class="c0 mk">documented \(marked uncoverable but covered\)|,
    "run-despite-marker pod detail is red and hatched with note";

  my @pod_errs = $html =~ /(data-errors="[^"]*pod)/g;
  is @pod_errs, 1, "only the stale pod is in the error filter";
}

sub main () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $libdir = File::Spec->catdir($tmpdir, "lib");
  make_path($libdir);
  _write_module($libdir, "Fixture.pm", $Fixture);
  _write_module($libdir, "PodFix.pm",  $Pod_fixture);

  test_main($tmpdir);
  test_pod($tmpdir) if eval "require Pod::Coverage; 1";
  done_testing;
}

main;

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
use Test::More import => [qw( diag done_testing is like plan )];
use Devel::Cover::Test::Showcase qw( run_cover slurp );

eval "require HTML::Entities; 1" or do {
  plan skip_all => "HTML::Entities not available";
  exit;
};

my $Fixture = <<'PERL';
package Fixture;
use strict;
use warnings;

sub after_return { my $x = shift; return 1; print "never\n" }
sub after_die    { eval { die "boom\n"; print "never\n" }; 1 }
sub both_run     { my $a = 1; my $b = 2; $a + $b }
# dc uncoverable statement count:3
sub excused_tail { my $x = 1; return $x; 0 }
# dc uncoverable statement count:4
sub excused_partial { my $x = shift; $x = 2 if $x; return $x; 0 }

1;
PERL

my %Line = (
  after_return    => 5,
  after_die       => 6,
  both_run        => 7,
  excused_tail    => 9,
  excused_partial => 11,
);

sub _write_module ($libdir, $name, $content) {
  my $path = File::Spec->catfile($libdir, $name);
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
}

sub _collect ($tmpdir, $code) {
  my $libdir   = File::Spec->catdir($tmpdir, "lib");
  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$libdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0"
    . ",-coverage,statement,branch"
    . qq( -e "$code" 2>&1);
  my $out = `$cmd`;
  die "Failed to create cover_db:\n$out\n" if $?;
  $cover_db
}

sub _report ($tmpdir, $cover_db) {
  my $outdir = File::Spec->catdir($tmpdir, "html_crisp");
  my ($out, $exit) = run_cover(
    "--report", "html_crisp", "--outputdir", $outdir,
    "--silent", $cover_db,
  );
  is $exit, 0, "cover --report html_crisp exits 0" or diag $out;
  my ($page) = grep !m|/coverage\.html$|, glob "$outdir/*.html";
  $page
}

sub _row ($html, $n) {
  my ($row)
    = $html =~ m|(<tr role="row"[^>]*>\n<td[^>]*><a id="L$n" .*?</tr>)|s;
  $row // ""
}

sub _count_cell ($row) {
  my ($cell) = $row =~ m|(<td role="cell" class="count[^>]*>[^<]*</td>)|;
  $cell // ""
}

sub test_uncovered_tail ($html, $name) {
  my $row = _row($html, $Line{$name});
  like $row, qr|data-cov="0"|,  "$name row has data-cov 0";
  like $row, qr|class="src-c0|, "$name row has the src-c0 class";
  is _count_cell($row),
    '<td role="cell" class="count exec-0" aria-label="executed 0 times">0</td>',
    "$name count cell shows 0";
}

sub main () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $libdir = File::Spec->catdir($tmpdir, "lib");
  make_path($libdir);
  _write_module($libdir, "Fixture.pm", $Fixture);

  my $code
    = "use Fixture; Fixture::after_return(); Fixture::after_die();"
    . " Fixture::both_run(); Fixture::excused_tail();"
    . " Fixture::excused_partial(1)";
  my $cover_db = _collect($tmpdir, $code);
  my $html     = slurp(_report($tmpdir, $cover_db));

  test_uncovered_tail($html, $_) for qw( after_return after_die );

  my @uncov = $html =~ /(data-cov="0")/g;
  is @uncov, 2, "exactly two rows are uncovered";

  my $both = _row($html, $Line{both_run});
  like $both,              qr|data-cov="1"|, "both_run row has data-cov 1";
  like _count_cell($both), qr|>1</td>$|,     "both_run count cell shows 1";

  my $excused = _row($html, $Line{excused_tail});
  like $excused, qr|data-cov="3"|, "excused_tail row has data-cov 3";
  like _count_cell($excused), qr|class="count exec-excused"|,
    "excused_tail count cell is excused";

  my $partial = _row($html, $Line{excused_partial});
  like $partial, qr|data-cov="2"|, "excused_partial row has data-cov 2";
  like _count_cell($partial), qr|class="count exec-partial\b|,
    "excused_partial count cell is partial";

  done_testing;
}

main;

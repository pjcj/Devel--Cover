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
use Test::More import => [qw( diag done_testing is is_deeply like plan )];
use Devel::Cover::Test::Showcase qw( run_cover slurp );

eval "require Template; 1" or do {
  plan skip_all => "Template not available";
  exit;
};

my $Fixture = <<'PERL';
package Anchor;
use strict;
use warnings;

sub two_branches {
  my ($x, $y) = @_;
  my $r = $x ? 1 : 0; my $s = $y ? 2 : 3;
  return $r + $s;
}

sub two_cond_types {
  my ($a, $b, $c) = @_;
  my $r = $a && $b || $c;
  return $r;
}

sub cond_and_branch {
  my ($a, $b) = @_;
  return 1 if $a && $b;
  return 0;
}

sub one { 1 } sub two { 2 }

1;
PERL

sub _fixture_line ($re) {
  my @lines = split /\n/, $Fixture;
  for my $i (0 .. $#lines) { return $i + 1 if $lines[$i] =~ $re }
  die "no fixture line matches $re";
}

sub _write_module ($libdir, $name, $content) {
  my $path = File::Spec->catfile($libdir, $name);
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
}

sub _collect ($tmpdir, $coverage, $code) {
  my $libdir   = File::Spec->catdir($tmpdir, "lib");
  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$libdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0"
    . ",-coverage,$coverage"
    . qq( -e "$code" 2>&1);
  my $out = `$cmd`;
  die "Failed to create cover_db:\n$out\n" if $?;
  $cover_db
}

sub _report ($tmpdir, $cover_db) {
  my $outdir = File::Spec->catdir($tmpdir, "html_basic");
  my ($out, $exit) = run_cover(
    "--report", "html_basic", "--outputdir", $outdir,
    "--silent", $cover_db,
  );
  is $exit, 0, "cover --report html_basic exits 0" or diag $out;
  my ($page) = grep !m|/coverage\.html$| && !m|--\w+\.html$|,
    glob "$outdir/*.html";
  ($outdir, $page)
}

sub _links ($html, $cr) {
  [sort $html =~ /href="[^"]*--\Q$cr\E\.html#([^"]*)"/g]
}

sub _anchors ($html) {
  [sort $html =~ /<a name="([^"]*)">/g]
}

sub main () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $libdir = File::Spec->catdir($tmpdir, "lib");
  make_path($libdir);
  _write_module($libdir, "Anchor.pm", $Fixture);

  my $cover_db = _collect(
    $tmpdir,
    "statement,branch,condition,mcdc,subroutine",
    "use Anchor; Anchor::two_branches(1, 0);"
      . " Anchor::two_cond_types(1, 1, 0); Anchor::cond_and_branch(1, 1);"
      . " Anchor::one(); Anchor::two()",
  );
  my ($outdir, $page) = _report($tmpdir, $cover_db);
  my $file_html = slurp($page);

  my %page;
  for my $cr (qw( branch condition mcdc subroutine )) {
    my ($p) = glob "$outdir/*--$cr.html";
    $page{$cr} = slurp($p);
    is_deeply _anchors($page{$cr}), _links($file_html, $cr),
      "$cr page anchors match the file page links";
  }

  my $bline = _fixture_line(qr/\$x \? 1/);
  like $file_html, qr|--branch\.html#$bline-2"|,
    "file page links to the second branch on a line";
  like $page{branch}, qr|<a name="$bline-2">|,
    "branch page anchors the second branch on a line";

  my $cline = _fixture_line(qr/&& \$b \|\|/);
  like $page{condition}, qr|<a name="$cline-1">|,
    "condition page anchors the first condition on a line";
  like $page{condition}, qr|<a name="$cline-2">|,
    "different-type conditions on one line get distinct anchors";

  my $sline = _fixture_line(qr/sub one/);
  like $page{subroutine}, qr|<a name="$sline-2">|,
    "subroutine page anchors the second sub on a line";

  done_testing;
}

main;

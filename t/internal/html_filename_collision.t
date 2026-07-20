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
use Test::More import => [qw( diag done_testing is is_deeply isnt like ok )];

use Devel::Cover::Html_Common    qw( unique_filenames );
use Devel::Cover::Test::Showcase qw( run_cover slurp );

sub test_mapping () {
  my $m = unique_filenames("X/Y.pm", "X-Y.pm");
  is $m->{"X-Y.pm"}, "X-Y-pm", "sorted-first path keeps the plain name";
  like $m->{"X/Y.pm"}, qr/\AX-Y-pm--[0-9a-f]{8}\z/,
    "collider gets a digest suffix";
  isnt $m->{"X/Y.pm"}, $m->{"X-Y.pm"}, "colliding paths map to unique names";

  my $m2 = unique_filenames("t/foo/bar.t", "t/foo-bar.t");
  isnt $m2->{"t/foo/bar.t"}, $m2->{"t/foo-bar.t"},
    "second collision pair maps to unique names";

  is unique_filenames("lib/Foo.pm")->{"lib/Foo.pm"}, "lib-Foo-pm",
    "non-colliding path is unchanged";

  is_deeply unique_filenames("X-Y.pm", "X/Y.pm"), $m,
    "mapping is independent of argument order";
}

# Build a cover_db over two source paths that both mangle to the same page
# name (X/Y.pm and X-Y.pm both become <path>-X-Y-pm), then run each report
# and require both sources to survive in the generated pages.
sub setup_colliding_db () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $libdir = File::Spec->catdir($tmpdir, "lib");
  make_path(File::Spec->catdir($libdir, "X"));

  my $slash = File::Spec->catfile($libdir, "X", "Y.pm");
  open my $sfh, ">", $slash or die "Cannot write $slash: $!";
  print $sfh "package X::Y;\nsub in_x_slash_y { 1 }\n1;\n";
  close $sfh or die "Cannot close $slash: $!";

  my $dash = File::Spec->catfile($libdir, "X-Y.pm");
  open my $dfh, ">", $dash or die "Cannot write $dash: $!";
  print $dfh "package X_Y;\nsub in_x_dash_y { 1 }\n1;\n";
  close $dfh or die "Cannot close $dash: $!";

  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  my $select   = quotemeta $libdir;
  # Pre-double backslashes - perl's -M q() processing halves them
  $select =~ s|\\|\\\\|g if $^O eq "MSWin32";
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $prog
    = "use X::Y; require q($dash); X::Y::in_x_slash_y(); X_Y::in_x_dash_y()";
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$libdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0,-select,$select"
    . qq( -e "$prog" 2>&1);
  my $out = `$cmd`;
  die "Failed to create cover_db:\n$out\n" if $?;

  ($tmpdir, $cover_db)
}

sub test_reports_keep_both ($tmpdir, $cover_db, $have_template) {
  for my $report (qw( html_basic html_subtle html_minimal html_crisp )) {
    next if $report =~ /^html_(basic|subtle)$/ && !$have_template;

    # Only html_basic and html_crisp accept the highlighter switches.
    my @highlight
      = $report =~ /^html_(basic|crisp)$/ ? ("-noppihtml", "-noperltidy") : ();

    my $outdir = File::Spec->catdir($tmpdir, $report);
    my ($out, $exit) = run_cover(
      "--report", $report,    "--outputdir", $outdir,
      "--silent", @highlight, $cover_db,
    );
    is $exit, 0, "$report: cover exits 0" or diag $out;

    # Exclude the index (coverage.html): it names subs in its summary even
    # when a file page is overwritten, which would mask the collision.
    my @pages = grep !m{/coverage\.html$}, glob "$outdir/*.html";
    ok(
      (grep { slurp($_) =~ /in_x_slash_y/ } @pages),
      "$report: X/Y.pm source appears in a file page",
    );
    ok(
      (grep { slurp($_) =~ /in_x_dash_y/ } @pages),
      "$report: X-Y.pm source appears in a file page",
    );
  }
}

sub main () {
  test_mapping;

  my $have_template = eval "require Template; 1";
  my ($tmpdir, $cover_db) = setup_colliding_db;
  test_reports_keep_both($tmpdir, $cover_db, $have_template);

  done_testing;
}

main;

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

# When no syntax highlighter runs (none installed, or both disabled) the
# source and coverage text reach the page unhighlighted, so they must still
# be escaped.
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

sub _report ($tmpdir, $cover_db, $report, @extra) {
  my $outdir = File::Spec->catdir($tmpdir, $report);
  my ($out, $exit) = run_cover(
    "--report", $report, "--outputdir", $outdir,
    "--silent", @extra,  $cover_db,
  );
  is $exit, 0, "cover --report $report exits 0" or diag $out;
  $outdir
}

# Disable syntax highlighting so raw source falls back unhighlighted.  Only the
# html_basic and html_crisp backends accept these options.
my @No_highlight = qw( -noppihtml -noperltidy );

sub test_html_basic ($tmpdir, $cover_db) {
  my $outdir = _report($tmpdir, $cover_db, "html_basic", @No_highlight);

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
  my $outdir      = _report($tmpdir, $cover_db, "html_crisp", @No_highlight);
  my ($file_page) = grep !m|/coverage\.html$|, glob "$outdir/*.html";
  my $html        = slurp($file_page);
  unlike $html, qr|<script>xss|, "html_crisp: file page escapes raw source";
  like $html, qr|&lt;script&gt;xss|,
    "html_crisp: file page contains escaped source";
}

# The covered file name reaches the report title, headings and links, and may
# contain markup characters, so it must be escaped there too and not only in
# the source body.  Windows file names cannot contain < > " so this is
# exercised on Unix only.
my $Meta = 'x<MARK>"&';

sub _setup_named_file () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $script = File::Spec->catfile($tmpdir, "$Meta.pl");
  open my $fh, ">", $script or die "Cannot write $script: $!";
  print $fh <<'PERL';
sub run {
  my $n = shift;
  if ($n > 0) {
    return "positive";
  }
  return "non-positive";
}
run(1);
run(-1);
PERL
  close $fh or die "Cannot close $script: $!";

  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my @cmd = (
    $^X, "-Iblib/lib", "-Iblib/arch",
    "-MDevel::Cover=-db,$cover_db,-silent,1,-merge,0", $script,
  );
  system(@cmd) == 0 or die "Failed to create cover_db (status $?)";

  ($tmpdir, $cover_db)
}

sub test_filename_escaped ($report, $tmpdir, $cover_db) {
  my $outdir = _report($tmpdir, $cover_db, $report);
  my $html   = join "\n", map slurp($_), glob "$outdir/*.html";
  unlike $html, qr|<MARK>|, "$report: raw file name metacharacters not emitted";
  like $html, qr|&lt;MARK&gt;|, "$report: file name metacharacters are escaped";
}

# The module name and version reach the coverage summary page from the covered
# distribution's MYMETA.json (or its directory name), so they may contain
# markup characters and must be escaped on the summary page too.
my $Have_cpan_meta = eval "require CPAN::Meta; 1";

sub _setup_meta () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $libdir = File::Spec->catdir($tmpdir, "lib");
  make_path($libdir);

  my $path = File::Spec->catfile($libdir, "Fixture.pm");
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $Fixture;
  close $fh or die "Cannot close $path: $!";

  my $meta = File::Spec->catfile($tmpdir, "MYMETA.json");
  open my $mh, ">", $meta or die "Cannot write $meta: $!";
  print $mh <<'JSON';
{
   "name" : "x<MARK>&",
   "version" : "1.0 x<MARK>&",
   "abstract" : "test",
   "dynamic_config" : 0,
   "generated_by" : "test",
   "license" : ["perl_5"],
   "meta-spec" : { "version" : 2 },
   "release_status" : "stable"
}
JSON
  close $mh or die "Cannot close $meta: $!";

  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my @cmd = (
    $^X,
    "-Iblib/lib",
    "-Iblib/arch",
    "-I$libdir",
    "-MDevel::Cover=-db,$cover_db,-dir,$tmpdir,-silent,1,-merge,0",
    "-e",
    "use Fixture; Fixture::decide(1, 1)",
  );
  system(@cmd) == 0 or die "Failed to create cover_db (status $?)";

  ($tmpdir, $cover_db)
}

sub test_meta_escaped ($tmpdir, $cover_db) {
  my $outdir = _report($tmpdir, $cover_db, "html_basic");
  my $html   = slurp(File::Spec->catfile($outdir, "coverage.html"));
  unlike $html, qr|<MARK>|,
    "html_basic: summary page does not emit raw module metadata";
  like $html, qr|&lt;MARK&gt;|,
    "html_basic: summary page escapes module metadata";
}

# The SCAR tooltip in the crisp report emits sub names, so escape them too.
sub test_crisp_scar_tip () {
  require Devel::Cover::Report::Html_crisp;
  my $tip = Devel::Cover::Report::Html_crisp::scar_tip({
    file_scar  => "5.0",
    file_cov   => 50,
    file_cc    => 3,
    file_crap  => 7.0,
    worst_subs => [{ name => "x<MARK>", crap => "9.0", scar => 20 }],
  });
  unlike $tip, qr|<MARK>|, "html_crisp: scar tip does not emit raw sub name";
  like $tip,   qr|&lt;MARK&gt;|, "html_crisp: scar tip escapes sub name";
}

sub main () {
  my ($tmpdir, $cover_db) = _setup;
  test_html_basic($tmpdir, $cover_db) if $Have_template;
  test_html_crisp($tmpdir, $cover_db);

  if ($Have_template && $Have_cpan_meta) {
    my ($t, $db) = _setup_meta;
    test_meta_escaped($t, $db);
  }

  test_crisp_scar_tip;

  unless ($^O eq "MSWin32") {
    my ($t, $db) = _setup_named_file;
    test_filename_escaped("html_crisp",   $t, $db);
    test_filename_escaped("html_minimal", $t, $db);
    test_filename_escaped("html_basic",   $t, $db) if $Have_template;
    test_filename_escaped("html_subtle",  $t, $db) if $Have_template;
  }

  done_testing;
}

main;

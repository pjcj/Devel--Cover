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

# Annotation text, headers and classes come from a plugin, so they may
# contain markup and must be escaped like every other value on the page.
my $Ann_text   = "Smith & Sons<script>alert(1)</script>";
my $Ann_header = "H<script>hdr</script>";
my $Ann_class  = 'x"><script>cls</script>';

sub _write_annotation ($tmpdir) {
  my $dir = File::Spec->catdir($tmpdir, "annlib", qw( Devel Cover Annotation ));
  make_path($dir);
  my $path = File::Spec->catfile($dir, "Evil.pm");
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh <<"PERL";
package Devel::Cover::Annotation::Evil;
use strict;
use warnings;
sub new    { bless {}, shift }
sub count  { 1 }
sub header { '$Ann_header' }
sub width  { 40 }
sub text   { '$Ann_text' }
sub error  { 0 }
sub class  { '$Ann_class' }
1;
PERL
  close $fh or die "Cannot close $path: $!";
  File::Spec->catdir($tmpdir, "annlib")
}

sub test_annotation_escaped ($tmpdir, $cover_db) {
  my $annlib = _write_annotation($tmpdir);
  local $ENV{PERL5LIB} = $annlib;
  my $outdir = _report(
    $tmpdir,        $cover_db, "html_basic", @No_highlight,
    "--annotation", "evil",
  );

  my ($file_page) = grep !m|/coverage\.html$| && !/--\w+\.html$/,
    glob "$outdir/*.html";
  my $html = slurp($file_page);

  unlike $html, qr|<script>alert\(1\)</script>|,
    "html_basic: annotation text is not written as raw markup";
  like $html, qr|&lt;script&gt;alert\(1\)&lt;/script&gt;|,
    "html_basic: annotation text is escaped";
  like $html, qr|Smith &amp; Sons|,
    "html_basic: an ampersand in annotation text is escaped";
  unlike $html, qr|<th> H<script>hdr</script> </th>|,
    "html_basic: annotation header is not written as raw markup";
  like $html, qr|H&lt;script&gt;hdr&lt;/script&gt;|,
    "html_basic: annotation header is escaped";
  unlike $html, qr|class="x"><script>cls</script>"|,
    "html_basic: annotation class is not written as raw markup";
  like $html, qr|x&quot;&gt;&lt;script&gt;cls&lt;/script&gt;|,
    "html_basic: annotation class is escaped";
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

# The common prefix of the covered file paths is printed on the crisp index
# page, so a directory name holding markup characters must be escaped there.
# It takes two covered files to produce a non-empty prefix.
sub _setup_marked_dir () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $libdir = File::Spec->catdir($tmpdir, "a&b<c");
  make_path($libdir);

  for my $mod (qw( AAA BBB )) {
    my $path = File::Spec->catfile($libdir, "$mod.pm");
    open my $fh, ">", $path or die "Cannot write $path: $!";
    print $fh "package $mod;\nsub go { 1 }\n1;\n";
    close $fh or die "Cannot close $path: $!";
  }

  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my @cmd = (
    $^X, "-Iblib/lib", "-Iblib/arch", "-I$libdir",
    "-MDevel::Cover=-db,$cover_db,-silent,1,-merge,0",
    "-e", "use AAA; use BBB; AAA::go; BBB::go",
  );
  system(@cmd) == 0 or die "Failed to create cover_db (status $?)";

  ($tmpdir, $cover_db)
}

sub test_common_prefix_escaped ($tmpdir, $cover_db) {
  my $outdir = _report($tmpdir, $cover_db, "html_crisp");
  my $html   = slurp(File::Spec->catfile($outdir, "coverage.html"));
  like $html, qr|common-prefix-path">[^<]*a&amp;b&lt;c|,
    "html_crisp: common prefix is escaped on the index page";
  unlike $html, qr|common-prefix-path">[^<]*a&b|,
    "html_crisp: raw prefix does not reach the page";
}

# The database path, the summary title and the crisp report id are printed on
# the summary page of each HTML report, so markup characters in them must be
# escaped there too.  run_cover joins its arguments through the shell, so the
# marked paths are quoted on the way in.
sub _sq ($s) { "'" . ($s =~ s/'/'\\''/gr) . "'" }

sub _setup_marked_db () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $dbdir  = File::Spec->catdir($tmpdir, "a<MARK>&d");
  make_path($dbdir);

  my $script = File::Spec->catfile($tmpdir, "run.pl");
  open my $fh, ">", $script or die "Cannot write $script: $!";
  print $fh "my \$x = 0;\n\$x++ for 1 .. 3;\n";
  close $fh or die "Cannot close $script: $!";

  my $cover_db = File::Spec->catdir($dbdir, "cover_db");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my @cmd = (
    $^X, "-Iblib/lib", "-Iblib/arch",
    "-MDevel::Cover=-db,$cover_db,-silent,1,-merge,0", $script,
  );
  system(@cmd) == 0 or die "Failed to create cover_db (status $?)";

  ($tmpdir, $cover_db)
}

sub test_summary_db_path_escaped ($report, $tmpdir, $cover_db) {
  my $outdir = File::Spec->catdir($tmpdir, $report);
  my ($out, $exit) = run_cover(
    "--report", $report, "--outputdir", $outdir,
    "--silent", _sq($cover_db),
  );
  is $exit, 0, "cover --report $report exits 0" or diag $out;
  my $html = slurp(File::Spec->catfile($outdir, "coverage.html"));
  unlike $html, qr|<MARK>|, "$report: raw db path is not on the summary page";
  like $html,   qr|&lt;MARK&gt;|, "$report: db path is escaped";
}

sub test_summary_title_escaped ($tmpdir, $cover_db) {
  my $outdir = File::Spec->catdir($tmpdir, "title");
  my ($out, $exit) = run_cover(
    "--report",       "html_minimal",   "--outputdir", $outdir,
    "--summarytitle", _sq("T<MARK>&t"), "--silent",    _sq($cover_db),
  );
  is $exit, 0, "cover --summarytitle exits 0" or diag $out;
  my $html = slurp(File::Spec->catfile($outdir, "coverage.html"));
  unlike $html, qr|<h1>T<MARK>&t</h1>|,
    "html_minimal: raw summary title is not in the heading";
  like $html, qr|<h1>T&lt;MARK&gt;&amp;t</h1>|,
    "html_minimal: summary title is escaped in the heading";
}

sub test_crisp_report_id_escaped ($tmpdir, $cover_db) {
  my $outdir = File::Spec->catdir($tmpdir, "out<MARK>&d");
  my ($out, $exit) = run_cover(
    "--report", "html_crisp", "--outputdir", _sq($outdir),
    "--silent", _sq($cover_db),
  );
  is $exit, 0, "cover --report html_crisp exits 0" or diag $out;
  my $html = slurp(File::Spec->catfile($outdir, "coverage.html"));
  unlike $html, qr/data-report-id="[^"]*<MARK>/,
    "html_crisp: raw output directory is not in the attribute";
  like $html, qr/data-report-id="[^"]*&lt;MARK&gt;/,
    "html_crisp: output directory is escaped in the attribute";
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

# Source files are read as bytes and each high-bit byte escaped into its own
# entity, so UTF-8 text such as an e-acute (0xC3 0xA9) garbles into
# &Atilde;&copy;.  The reports must guess the source encoding (strict UTF-8,
# falling back to Latin-1), escape only HTML-unsafe characters and write
# UTF-8 output.  The regex string below guards the original ampersand
# escaping problem: it must render with &amp;, never a bare ampersand.
my $E_utf8   = "\xC3\xA9";
my $E_latin1 = "\xE9";

my $Encoded_fixture = <<'PERL';
package Encoded;
use strict;
use warnings;

sub greet {
  my ($name) = @_;
  my $re = '(?&param)?+';
  return $name eq "bEbE" ? "yes" : $re;
}

1;
PERL

sub _setup_encoded ($e) {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $libdir = File::Spec->catdir($tmpdir, "lib");
  make_path($libdir);

  my $path = File::Spec->catfile($libdir, "Encoded.pm");
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $Encoded_fixture =~ s/bEbE/b${e}b$e/gr;
  close $fh or die "Cannot close $path: $!";

  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my @cmd = (
    $^X, "-Iblib/lib", "-Iblib/arch", "-I$libdir",
    "-MDevel::Cover=-db,$cover_db,-silent,1,-merge,0",
    "-e", "use Encoded; Encoded::greet(q(x))",
  );
  system(@cmd) == 0 or die "Failed to create cover_db (status $?)";

  ($tmpdir, $cover_db)
}

sub _all_pages ($outdir) {
  join "\n", map slurp($_), glob "$outdir/*.html"
}

sub test_unicode_source ($report, $tmpdir, $cover_db, @extra) {
  my $outdir = _report($tmpdir, $cover_db, $report, @extra);
  my $html   = _all_pages($outdir);
  like $html, qr/b\xC3\xA9b/, "$report: non-ASCII source renders as UTF-8";
  unlike $html, qr/&Atilde;|&eacute;|&#233;|&#xe9;/i,
    "$report: no byte-wise entities for non-ASCII source";
  like $html, qr/\(\?&amp;param\)\?\+/,
    "$report: ampersand in source is escaped";
  $html
}

sub test_unicode_highlighted ($report, $tmpdir, $cover_db) {
  my $outdir = _report($tmpdir, $cover_db, $report);
  my $html   = _all_pages($outdir);
  like $html, qr/b(\xC3\xA9|&eacute;|&#233;|&#xe9;)b/i,
    "$report: highlighted non-ASCII source renders correctly";
  unlike $html, qr/&Atilde;/,
    "$report: highlighted source is not escaped byte-wise";
  like $html, qr/\(\?&amp;param\)/,
    "$report: highlighted ampersand in source is escaped";
}

sub test_decode_guess () {
  require Devel::Cover::Html_Common;
  my $d = \&Devel::Cover::Html_Common::decode_guess;
  is $d->("b\xC3\xA9b\xC3\xA9"), "b\x{e9}b\x{e9}", "UTF-8 bytes are decoded";
  is $d->("b\xE9b\xE9"),         "b\x{e9}b\x{e9}", "Latin-1 bytes are decoded";
  my $wide = "snow \x{2603}";
  is $d->($wide), $wide, "wide-character strings pass through";
}

sub test_latin1_source ($report, $tmpdir, $cover_db, @extra) {
  my $outdir = _report($tmpdir, $cover_db, $report, @extra);
  my $html   = _all_pages($outdir);
  like $html, qr/b\xC3\xA9b/, "$report: Latin-1 source is transcoded to UTF-8";
  unlike $html, qr/b\xE9b/,   "$report: no raw Latin-1 bytes in output";
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
  test_annotation_escaped($tmpdir, $cover_db) if $Have_template;

  if ($Have_template && $Have_cpan_meta) {
    my ($t, $db) = _setup_meta;
    test_meta_escaped($t, $db);
  }

  test_crisp_scar_tip;
  test_decode_guess;

  {
    my ($t, $db) = _setup_encoded($E_utf8);
    test_unicode_source("html_crisp", $t, $db, @No_highlight);
    test_unicode_source("html_minimal", $t, $db);
    if ($Have_template) {
      test_unicode_source("html_basic", $t, $db, @No_highlight);
      my $html = test_unicode_source("html_subtle", $t, $db);
      like $html, qr/charset=utf-8/i, "html_subtle: declares a utf-8 charset";
    }
  }

  if (eval "require PPI::HTML; 1") {
    my ($t, $db) = _setup_encoded($E_utf8);
    test_unicode_highlighted("html_crisp", $t, $db);
    test_unicode_highlighted("html_basic", $t, $db) if $Have_template;
  }

  {
    my ($t, $db) = _setup_encoded($E_latin1);
    test_latin1_source("html_crisp",   $t, $db, @No_highlight);
    test_latin1_source("html_minimal", $t, $db);
    test_latin1_source("html_basic", $t, $db, @No_highlight) if $Have_template;
  }

  unless ($^O eq "MSWin32") {
    my ($t, $db) = _setup_named_file;
    test_filename_escaped("html_crisp",   $t, $db);
    test_filename_escaped("html_minimal", $t, $db);
    test_filename_escaped("html_basic",   $t, $db) if $Have_template;
    test_filename_escaped("html_subtle",  $t, $db) if $Have_template;

    my ($td, $cdb) = _setup_marked_dir;
    test_common_prefix_escaped($td, $cdb);

    my ($mt, $mdb) = _setup_marked_db;
    test_summary_db_path_escaped("html_minimal", $mt, $mdb);
    if ($Have_template) {
      test_summary_db_path_escaped("html_basic",  $mt, $mdb);
      test_summary_db_path_escaped("html_subtle", $mt, $mdb);
    }
    test_summary_title_escaped($mt, $mdb);
    test_crisp_report_id_escaped($mt, $mdb);
  }

  done_testing;
}

main;

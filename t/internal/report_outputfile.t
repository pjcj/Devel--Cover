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
use JSON::PP   ();
use Test::More import => [qw( diag done_testing is like ok unlike )];
use Devel::Cover::Test::Showcase qw(
  create_cover_db
  run_cover
  setup_lib_dir
  slurp
);

my ($Tmpdir, $Libdir) = setup_lib_dir;
my $Cover_db = create_cover_db($Tmpdir, $Libdir);

sub outdir ($name) { File::Spec->catdir($Tmpdir, $name) }

sub report_to_file ($name, $report, $file, @extra) {
  my $dir = outdir($name);
  my ($out, $exit) = run_cover(
    "--report",    $report, "--outputfile", $file,
    "--outputdir", $dir,    "--nosummary",  "--silent",
    @extra,        $Cover_db,
  );
  is $exit, 0, "cover --report $report --outputfile exits 0" or diag $out;
  my $path = File::Spec->catfile($dir, $file);
  ok -s $path, "$report report written to $file" or return ($out, $dir, "");
  ($out, $dir, slurp($path))
}

sub test_text_report () {
  my ($out, $dir, $content) = report_to_file("text", "text", "out.txt");
  like $content, qr/Module Summary/, "text report content is in the file";
  unlike $out,   qr/Module Summary/, "text report is not printed to stdout";
}

sub test_compilation_report () {
  report_to_file("compilation", "compilation", "out.cmp");
}

sub test_json_summary_report () {
  my ($out, $dir, $content)
    = report_to_file("json_summary", "json_summary", "out.json");
  my $json = eval { JSON::PP::decode_json($content) } // {};
  ok $json->{summary}, "json_summary file parses as JSON" or diag $@;
  ok !-e File::Spec->catfile($dir, "cover.json"),
    "json_summary writes no cover.json beside the named file";
}

sub test_mixed_reports () {
  my $dir = outdir("mixed");
  my ($out, $exit) = run_cover(
    "--report",     "json",     "--report",    "text",
    "--outputfile", "out.mix",  "--outputdir", $dir,
    "--nosummary",  "--silent", $Cover_db,
  );
  is $exit, 0, "cover with mixed reports exits 0" or diag $out;
  like slurp(File::Spec->catfile($dir, "out.mix")), qr/Module Summary/,
    "the last report given owns the named file";
}

sub test_unknown_option () {
  my ($out, $exit) = run_cover(
    "--report", "text", "--outputfyle", "x.txt", "--silent", $Cover_db,
  );
  is $exit, 1, "a genuine typo still exits 1";
  like $out, qr/Unknown option/, "a genuine typo is still reported";
}

sub main () {
  test_text_report;
  test_compilation_report;
  test_json_summary_report;
  test_mixed_reports;
  test_unknown_option;
  done_testing;
}

main;

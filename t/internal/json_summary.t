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
use Test::More import => [qw( diag done_testing is isa_ok ok plan )];
use Devel::Cover::Test::Showcase qw(
  create_cover_db
  run_cover
  setup_lib_dir
  slurp
);

eval "require JSON::MaybeXS; 1" or do {
  plan skip_all => "JSON::MaybeXS not available";
  exit;
};

# json_summary is the per-file/total summary feed used by cpancover (and by
# anyone wanting badge-style numbers).  It must NOT include per-line detail.
sub test_json_summary_report () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);
  my $outdir   = File::Spec->catdir($tmpdir, "json");

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "json_summary",
    "--outputdir",  $outdir, "--silent", $cover_db,
  );

  is $exit, 0, "cover --report json_summary exits 0" or diag $out;

  my $path = File::Spec->catfile($outdir, "cover.json");
  ok -e $path, "cover.json was generated";

  my $json = JSON::MaybeXS->new(utf8 => 1)->decode(slurp($path));

  ok exists $json->{runs},    "runs key present";
  ok exists $json->{summary}, "summary key present";
  ok !exists $json->{files},
    "files key absent (discriminator vs. detailed json reporter)";

  isa_ok $json->{runs}, "ARRAY", "runs";
  ok $json->{runs}->@* >= 1, "at least one run recorded";

  ok defined $json->{summary}{Total}{statement}{percentage},
    "summary->Total->statement->percentage is defined";
}

sub main () {
  test_json_summary_report;
  done_testing;
}

main;

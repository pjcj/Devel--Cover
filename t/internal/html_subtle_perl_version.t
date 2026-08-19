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

sub _setup () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $script = File::Spec->catfile($tmpdir, "run.pl");
  open my $fh, ">", $script or die "Cannot write $script: $!";
  print $fh "my \$x = 0;\n\$x++ for 1 .. 3;\n";
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

# The report once read $^V as a v-string, taking the ord of each character.
# $^V has been a version object since 5.10, so that spelt v5.44.0 as
# 118.53.46.52.52.46.48.
sub test_perl_version_is_printed_as_a_version ($tmpdir, $cover_db) {
  my $outdir = File::Spec->catdir($tmpdir, "out");
  my ($out, $exit) = run_cover(
    "--report", "html_subtle", "--outputdir", $outdir,
    "--silent", $cover_db,
  );
  is $exit, 0, "cover --report html_subtle exits 0" or diag $out;
  my $html = join "\n", map slurp($_), glob "$outdir/*.html";
  my $v    = "$^V";
  like $html,   qr/Perl version/, "a page shows the perl version row";
  like $html,   qr/\Q$v\E/,       "pages name the running perl version";
  unlike $html, qr/\b118\.53\./,  "pages do not print character codes";
}

sub main () {
  my ($tmpdir, $cover_db) = _setup;
  test_perl_version_is_printed_as_a_version($tmpdir, $cover_db);
  done_testing;
}

main;

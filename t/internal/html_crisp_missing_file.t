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
use Test::More import => [qw( diag done_testing is ok plan unlike )];
use Devel::Cover::Test::Showcase qw(
  create_cover_db
  run_cover
  setup_lib_dir
  slurp
);

eval "require HTML::Entities; 1" or do {
  plan skip_all => "HTML::Entities not available";
  exit;
};

sub main () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);

  # Remove one covered source file after collection, before reporting, so the
  # database references a file that no longer exists on disk.
  my $missing = File::Spec->catfile($libdir, "Covered", "Utils.pm");
  unlink $missing or die "Cannot unlink $missing: $!";

  my $outdir = File::Spec->catdir($tmpdir, "html");
  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "html_crisp",
    "--outputdir",  $outdir, "--silent", $cover_db,
  );
  is $exit, 0, "report generated with a missing source file" or diag $out;

  my @pages = glob "$outdir/*.html";
  ok @pages, "pages were generated";
  is 0 + (grep /-Covered-Utils-pm\.html$/, @pages), 0,
    "no page is written for the missing file";

  # The leading hyphen (mangled path separator) and capital C keep this from
  # matching the Uncovered/Utils.pm twin, which exists and must keep its page.
  for my $page (@pages) {
    my $name = $page =~ s{.*/}{}r;
    unlike slurp($page), qr/href="[^"]*-Covered-Utils-pm\.html/,
      "$name has no link to the missing file's page";
  }

  done_testing;
}

main;

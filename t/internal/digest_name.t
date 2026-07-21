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
use File::Path qw( remove_tree );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing is ok )];

use Devel::Cover::DB ();

# The same content can be recorded under several names - a copy or symlink of
# a script run from a temp directory that is deleted before the report is
# built.  The canonical name for the digest must be a path that still exists,
# not whichever name the newest run happened to use, or the report shows an
# unlinkable stub and drops the real file.

my $Tmpdir = realpath(tempdir(CLEANUP => 1));

sub write_file ($path, $content) {
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
}

sub run_covered ($db, $script) {
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd = "$^X -Iblib/lib -Iblib/arch"
    . " -MDevel::Cover=-db,$db,-silent,1 $script 2>&1";
  my $out = `$cmd`;
  is $?, 0, "covered run of $script exits 0" or diag $out;
}

sub main () {
  my $keep_dir = File::Spec->catdir($Tmpdir, "keep");
  my $gone_dir = File::Spec->catdir($Tmpdir, "gone");
  for my $dir ($keep_dir, $gone_dir) {
    mkdir $dir or die "Cannot mkdir $dir: $!";
  }

  my $content = qq(my \$x = shift // 1;\nprint "ran\\n";\n);
  my $real    = File::Spec->catfile($keep_dir, "script.pl");
  my $alias   = File::Spec->catfile($gone_dir, "script-alias.pl");
  write_file($_, $content) for $real, $alias;

  # Removing the digests cache between the runs stands in for a parent
  # process clobbering it, so the alias run records its own name.  The alias
  # run is the newest and is processed first when the cover data is built
  my $db = File::Spec->catdir($Tmpdir, "cover_db");
  run_covered($db, $real);
  unlink File::Spec->catfile($db, "digests");
  run_covered($db, $alias);
  remove_tree($gone_dir);

  my $cover = Devel::Cover::DB->new(db => $db)->merge_runs->cover;
  my %item;
  @item{ $cover->items } = ();
  # Devel::Cover records Windows paths with forward slashes
  tr|\\|/| for $real, $alias;
  ok exists $item{$real},   "the surviving path is the canonical name";
  ok !exists $item{$alias}, "the vanished alias is not reported";

  my $file = $cover->file($real) or return done_testing;
  my $l    = $file->statement->location(1);
  ok $l, "the surviving path holds the statement data";
  is $l && $l->[0]->covered, 2, "with the counts of both runs merged";

  done_testing
}

main

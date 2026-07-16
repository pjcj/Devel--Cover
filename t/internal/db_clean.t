#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# clean sweeps stale .lock files from the database directory. Locking is
# flock on the lock file's path, so a held lock must never be unlinked -
# doing so hands the next writer a fresh inode and two processes then hold
# "exclusive" locks on the same data file.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Fcntl      qw( :flock );
use File::Path qw( make_path );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing ok )];

use Devel::Cover::DB ();

my $Tmpdir = tempdir(CLEANUP => 1);

sub fresh_db ($label) {
  my $dir = File::Spec->catdir($Tmpdir, $label);
  make_path($dir);
  my $db = Devel::Cover::DB->new;
  $db->{db} = $dir;
  ($db, $dir)
}

sub touch ($path) {
  open my $fh, ">", $path or die "Cannot create $path: $!";
  close $fh or die "Cannot close $path: $!";
  $path
}

sub test_held_lock_survives () {
  my ($db, $dir) = fresh_db("held");
  my $held = touch("$dir/digests.lock");
  open my $fh, "+<", $held or die "Cannot open $held: $!";
  flock $fh, LOCK_EX or die "Cannot lock $held: $!";

  $db->clean;

  ok -e $held, "clean: leaves a held lock file in place";
  close $fh or die "Cannot close $held: $!";
}

sub test_stale_lock_removed () {
  my ($db, $dir) = fresh_db("stale");
  my $stale = touch("$dir/cover.15.lock");

  $db->clean;

  ok !-e $stale, "clean: removes an unheld lock file";
}

sub test_non_lock_file_untouched () {
  my ($db, $dir) = fresh_db("data");
  my $data = touch("$dir/cover.15");

  $db->clean;

  ok -e $data, "clean: leaves non-lock files alone";
}

sub test_subdirectory_lock_removed () {
  my ($db, $dir) = fresh_db("subdir");
  make_path("$dir/structure");
  my $stale = touch("$dir/structure/0123456789abcdef.lock");

  $db->clean;

  ok !-e $stale, "clean: removes unheld lock files in subdirectories";
}

sub main () {
  test_held_lock_survives;
  test_stale_lock_removed;
  test_non_lock_file_untouched;
  test_subdirectory_lock_removed;
}

main;
done_testing;

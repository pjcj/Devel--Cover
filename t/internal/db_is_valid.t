#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# is_valid decides whether a directory is a coverage database. It is the only
# guard before `cover -delete` destroys the directory, so housekeeping names
# must match entry names in full - substring matches let foreign directories
# pass and be deleted.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use File::Path qw( make_path );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing ok )];

use Devel::Cover::DB ();

my $Tmpdir = tempdir(CLEANUP => 1);
my $N      = 0;

sub db_with (@entries) {
  my $path = File::Spec->catdir($Tmpdir, "db" . ++$N);
  make_path($path);
  for my $entry (@entries) {
    if ($entry =~ s|/$||) {
      make_path(File::Spec->catdir($path, $entry));
    } else {
      my $file = File::Spec->catfile($path, $entry);
      open my $fh, ">", $file or die "Cannot write $file: $!";
      close $fh or die "Cannot close $file: $!";
    }
  }
  $path
}

sub is_valid ($path) {
  my $db = Devel::Cover::DB->new;
  $db->{db} = $path;
  local $SIG{__WARN__} = sub { };
  $db->is_valid
}

sub test_foreign_directories_are_invalid () {
  ok !is_valid(db_with(qw( test_runs/ infrastructure/ debuglog.txt ))),
    "is_valid: housekeeping names must not match as substrings";
  ok !is_valid(db_with("xAppleDouble")),
    "is_valid: the dot in .AppleDouble is not a wildcard";
  ok !is_valid(db_with("runs.old/")),
    "is_valid: housekeeping names must not match as prefixes";
  ok !is_valid(db_with("stranger.txt")), "is_valid: unknown entry is invalid";
  ok !is_valid(db_with("debuglog/")),
    "is_valid: debuglog is no longer housekeeping";
}

sub test_real_databases_are_valid () {
  ok is_valid(File::Spec->catdir($Tmpdir, "missing")),
    "is_valid: a missing path is valid";
  ok is_valid(db_with()), "is_valid: an empty directory is valid";
  ok is_valid(db_with(qw( cover.15 anything_at_all ))),
    "is_valid: cover.15 marks a database regardless of other entries";
  ok is_valid(
    db_with(qw( runs/ structure/ digests .AppleDouble cover.15.lock ))),
    "is_valid: all housekeeping entries are accepted";
  ok is_valid(db_with(qw( runs/ digests.tmp.12345 ))),
    "is_valid: a leaked atomic-write temp file is accepted";
}

sub main () {
  test_foreign_directories_are_invalid;
  test_real_databases_are_valid;
}

main;
done_testing;

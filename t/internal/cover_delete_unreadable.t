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

use File::Path qw( make_path );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing is ok unlike )];
use Devel::Cover::Test::Showcase qw( run_cover );

sub write_unreadable ($dir) {
  make_path($dir);
  my $file = File::Spec->catfile($dir, "cover.15");
  open my $fh, ">", $file or die "Cannot write $file: $!";
  print $fh "not a coverage database\n";
  close $fh or die "Cannot close $file: $!";
}

sub test_delete_unreadable () {
  my $db = File::Spec->catdir(tempdir(CLEANUP => 1), "cover_db");
  write_unreadable($db);
  write_unreadable(File::Spec->catdir($db, "runs", "1000.1.00001"));
  my ($out, $exit) = run_cover("-delete", $db);
  is $exit, 0, "-delete of an unreadable database exits 0" or diag $out;
  unlike $out, qr/Warning/, "-delete prints no warning";
  ok !-e $db, "-delete removes the unreadable database";
}

sub test_delete_foreign_directory () {
  my $dir = File::Spec->catdir(tempdir(CLEANUP => 1), "foreign");
  make_path($dir);
  my $file = File::Spec->catfile($dir, "stray.txt");
  open my $fh, ">", $file or die "Cannot write $file: $!";
  print $fh "not part of a database\n";
  close $fh or die "Cannot close $file: $!";
  my ($out, $exit) = run_cover("-delete", $dir);
  is $exit, 0, "-delete of a foreign directory exits 0" or diag $out;
  ok -d $dir,  "-delete keeps the foreign directory";
  ok -e $file, "-delete keeps the file in the foreign directory";
  my $found = () = $out =~ /found stray\.txt/g;
  is $found, 1, "-delete warns about the file once" or diag $out;
  my $invalid = () = $out =~ /is an invalid database/g;
  is $invalid, 1, "-delete reports the invalid database once" or diag $out;
}

sub main () {
  test_delete_unreadable;
  test_delete_foreign_directory;
}

main;
done_testing;

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

use File::Find ();
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing is ok plan )];

use Devel::Cover::DB           ();
use Devel::Cover::DB::IO::Base ();

BEGIN {
  plan skip_all => "file modes are not carried on Windows" if $^O eq "MSWin32";
}

my $Loose   = 0666;
my $Default = 0666 & ~0022;

sub lock_files ($dir) {
  my @locks;
  File::Find::find(sub { push @locks, $File::Find::name if /\.lock$/ }, $dir);
  sort @locks
}

sub check_modes ($db, $expected, $desc) {
  my @locks = lock_files($db);
  ok @locks, "$desc: lock files were created";
  my @wrong = grep { ((stat)[2] & 07777) != $expected } @locks;
  is @wrong, 0, sprintf "$desc: every lock file is %04o", $expected
    or diag join "\n", map sprintf("%04o %s", (stat)[2] & 07777, $_), @wrong;
}

sub test_io_base ($loose, $expected, $desc) {
  my $tmpdir = tempdir(CLEANUP => 1);
  my $file   = File::Spec->catfile($tmpdir, "data");
  my $io = Devel::Cover::DB::IO::Base->new($loose ? (loose_perms => 1) : ());
  $io->write_fh($file, sub ($fh) { print $fh "data" });

  is +(stat "$file.lock")[2] & 07777, $expected,
    sprintf "$desc: lock file is %04o", $expected;
}

sub collect ($tmpdir, $db, @options) {
  my $prog = File::Spec->catfile($tmpdir, "covered.pl");
  open my $fh, ">", $prog or die "Can't open $prog: $!";
  print $fh "my \$x = 1;\n";
  close $fh or die "Can't close $prog: $!";

  my $options = join ",", "-db", $db, "-silent", 1, @options;
  my @cmd     = ($^X, "-Mblib", "-MDevel::Cover=$options", $prog);
  is system(@cmd), 0, "collection ran" or diag "failed: @cmd";
}

sub test_collection ($loose, $expected, $desc) {
  my $tmpdir = tempdir(CLEANUP => 1);
  my $db     = File::Spec->catfile($tmpdir, "cover_db");

  collect($tmpdir, $db, $loose ? ("-loose_perms", 1) : ());
  check_modes($db, $expected, "$desc collection");

  Devel::Cover::DB->new(db => $db, loose_perms => $loose)->merge_runs;
  check_modes($db, $expected, "$desc merge");
}

sub main () {
  test_io_base(1, $Loose,   "loose_perms");
  test_io_base(0, $Default, "default perms");
  test_collection(1, $Loose,   "loose");
  test_collection(0, $Default, "default");
  done_testing;
}

umask 0022;
main;

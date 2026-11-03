#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Cwd     ();
use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Digest::MD5 ();
use File::Path  qw( make_path );
use File::Spec  ();
use File::Temp  qw( tempdir );
use Test::More import => [qw( done_testing is ok )];

my $Root = Cwd::cwd();

use Devel::Cover::DB ();

my $Tmpdir = Cwd::realpath(tempdir(CLEANUP => 1));
my $Lib    = File::Spec->catdir($Tmpdir, "lib");

sub write_file ($path, $text) {
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $text;
  close $fh or die "Cannot close $path: $!";
  $path
}

sub md5 ($path) {
  open my $fh, "<", $path or die "Cannot read $path: $!";
  binmode $fh;
  my $digest = Digest::MD5->new->addfile($fh)->hexdigest;
  close $fh or die "Cannot close $path: $!";
  $digest
}

sub setup () {
  make_path($Lib);
  for my $m (qw( M1 M2 )) {
    write_file("$Lib/$m.pm", "package $m;\nsub run { 1 }\n1;\n");
  }
  write_file("$Tmpdir/all.pl", "use M1;\nuse M2;\nM1::run();\nM2::run();\n");
  write_file("$Tmpdir/one.pl", "use M1;\nM1::run();\n");
}

# Run a script under Devel::Cover into the db.
sub run_cover ($script, $db) {
  my @inc = map { "-I$_" } "$Root/blib/arch", "$Root/blib/lib", "$Root/lib",
    $Lib;
  system($^X, @inc, "-MDevel::Cover=-db,$db,-silent,1", "$Tmpdir/$script") == 0
    or die "Failed to run $script under Devel::Cover: $?";
}

sub statement_covered ($db, $name) {
  my ($file) = grep m|/\Q$name\E$|, $db->cover->items;
  $file ? $db->summary($file, "statement", "covered") : 0
}

sub test_untouched_structure () {
  my $db = File::Spec->catdir($Tmpdir, "cover_db");
  run_cover("all.pl", $db);

  my $old = time - 3600;
  opendir my $dh, "$db/structure" or die "Can't opendir $db/structure: $!";
  my @files = map "$db/structure/$_", grep !/^\./, readdir $dh;
  closedir $dh or die "Can't closedir $db/structure: $!";
  utime $old, $old, @files;

  run_cover("one.pl", $db);

  my $m2 = "$db/structure/" . md5("$Lib/M2.pm");
  ok -e $m2, "M2 has a structure file";
  my $mtime = (stat $m2)[9];
  is $mtime, $old, "one.pl leaves the M2 structure file alone";
  my $one = "$db/structure/" . md5("$Tmpdir/one.pl");
  ok -e $one, "one.pl has a structure file";

  my $merged = Devel::Cover::DB->new(db => $db)->merge_runs;
  $merged->calculate_summary(statement => 1);
  ok statement_covered($merged, "M1.pm"), "merged db covers M1.pm statements";
  ok statement_covered($merged, "M2.pm"), "merged db covers M2.pm statements";
}

sub main () {
  setup;
  test_untouched_structure;
}

main;
done_testing;

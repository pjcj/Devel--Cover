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

use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing is is_deeply isnt like ok )];

use Devel::Cover::DB             ();
use Devel::Cover::Test::Showcase qw( run_cover );

my $Junk = "not a coverage database";
my $Run  = {
  OS        => $^O,
  perl      => "5.26.3",
  dir       => "/x",
  run       => "t.pl",
  name      => "x",
  version   => "1",
  start     => 1,
  finish    => 2,
  collected => ["statement"],
  count     => { "a.pl" => { statement => [1, 1] } },
  digests   => { "a.pl" => "abc" },
};

sub write_run ($dir, $name) {
  my $runs = "$dir/runs";
  -d $runs or mkdir $runs or die "Cannot mkdir $runs: $!";
  Devel::Cover::DB->new(
    base => $dir,
    db   => "$runs/$name",
    runs => { $name => $Run },
  )->write;
}

sub write_main ($dir) {
  Devel::Cover::DB->new(
    base => $dir,
    db   => $dir,
    runs => { "999.1.00001" => { %$Run, name => "old" } },
  )->write;
}

sub junk ($file) {
  open my $fh, ">", $file or die "Cannot open $file: $!";
  print $fh $Junk or die "Cannot write $file: $!";
  close $fh       or die "Cannot close $file: $!";
}

sub slurp ($file) {
  open my $fh, "<", $file or die "Cannot open $file: $!";
  binmode $fh;
  my $bytes = do { local $/; <$fh> };
  close $fh or die "Cannot close $file: $!";
  $bytes
}

sub run_entries ($dir) {
  opendir my $dh, "$dir/runs" or die "Cannot opendir $dir/runs: $!";
  my @entries = sort grep !/^\.\.?$/, readdir $dh;
  closedir $dh or die "Cannot closedir $dir/runs: $!";
  \@entries
}

sub test_unreadable_main_db () {
  my $dir  = tempdir(CLEANUP => 1);
  my $file = "$dir/cover.15";
  write_run($dir, "1000.1.00001");
  write_main($dir);
  junk($file);

  my $ok = eval { Devel::Cover::DB->new(db => $dir); 1 };
  ok !$ok, "new dies on a main database that it cannot read";
  like $@, qr/^Devel::Cover: cannot read database file \Q$file\E:/,
    "the error names the file";
  is slurp($file), $Junk, "the main database is untouched";
  is_deeply run_entries($dir), ["1000.1.00001"], "the run is kept";
}

sub test_unreadable_main_db_in_merge () {
  my $dir  = tempdir(CLEANUP => 1);
  my $file = "$dir/cover.15";
  write_run($dir, "1000.1.00001");
  my $db = Devel::Cover::DB->new(db => $dir);
  junk($file);

  my $ok = eval { $db->merge_runs; 1 };
  ok !$ok, "merge_runs dies on a main database that it cannot read";
  like $@, qr/^Devel::Cover: cannot read database file \Q$file\E:/,
    "the error names the file";
  is slurp($file), $Junk, "the main database is untouched";
  is_deeply run_entries($dir), ["1000.1.00001"],
    "the run is kept under its own name";
}

sub test_unreadable_run () {
  my $dir  = tempdir(CLEANUP => 1);
  my $file = "$dir/runs/1001.1.00001/cover.15";
  write_main($dir);
  write_run($dir, "1000.1.00001");
  write_run($dir, "1001.1.00001");
  junk($file);
  my $before = slurp("$dir/cover.15");

  my $db = Devel::Cover::DB->new(db => $dir);
  my $ok = eval { $db->merge_runs; 1 };
  ok !$ok, "merge_runs dies on a run that it cannot read";
  like $@, qr/^Devel::Cover: cannot read database file \Q$file\E:/,
    "the error names the file";
  ok slurp("$dir/cover.15") eq $before, "the main database is untouched";
  is_deeply run_entries($dir), ["1000.1.00001", "1001.1.00001"],
    "both runs are kept under their own names";
}

sub test_no_data () {
  my $dir  = tempdir(CLEANUP => 1);
  my $file = "$dir/cover.15";
  junk($file);
  my $db = Devel::Cover::DB->new;

  {
    no warnings "redefine";
    local *Devel::Cover::DB::IO::read = sub { undef };
    my $ok = eval { $db->read($file); 1 };
    ok !$ok, "read dies when the reader returns no data";
    like $@, qr/cannot read database file \Q$file\E: no data/,
      "the error names the file and the lack of data";
  }
}

sub test_silent_still_dies () {
  my $dir  = tempdir(CLEANUP => 1);
  my $file = "$dir/cover.15";
  junk($file);

  local $Devel::Cover::Silent = 1;
  my $ok = eval { Devel::Cover::DB->new->read($file); 1 };
  ok !$ok, "read dies on a file that it cannot read when silenced";
}

sub test_cover_exits_with_error () {
  my $dir  = tempdir(CLEANUP => 1);
  my $file = "$dir/cover.15";
  write_run($dir, "1000.1.00001");
  junk($file);

  my ($out, $exit) = run_cover("-no-gcov", "-report", "text", $dir);
  isnt $exit, 0, "cover exits with an error" or diag $out;
  like $out, qr/cannot read database file/, "cover reports the failed read";
  is slurp($file), $Junk, "the main database is untouched";
  is_deeply run_entries($dir), ["1000.1.00001"], "the run is kept";
}

sub main () {
  test_unreadable_main_db;
  test_unreadable_main_db_in_merge;
  test_unreadable_run;
  test_no_data;
  test_silent_still_dies;
  test_cover_exits_with_error;
}

main;
done_testing;

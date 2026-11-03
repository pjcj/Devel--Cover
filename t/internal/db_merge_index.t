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
use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is is_deeply ok )];

use Devel::Cover::DB ();

my $Tmpdir = tempdir(CLEANUP => 1);

sub run_with ($digest) {
  +{
    digests => { "f.pl" => $digest },
    count   => { "f.pl" => { statement => [1] } },
    vec     => { "f.pl" => { statement => { vec => "", size => 1 } } },
  }
}

sub db_with (%runs) {
  Devel::Cover::DB->new(
    runs => { map { $_ => run_with($runs{$_}) } keys %runs })
}

sub merge_capturing ($db, $from) {
  local $Devel::Cover::Silent = 0;
  my $stderr = "";
  open my $save, ">&", \*STDERR or die "Cannot dup STDERR: $!";
  close STDERR or die "Cannot close STDERR: $!";
  open STDERR, ">", \$stderr or die "Cannot capture STDERR: $!";
  eval { $db->merge($from) };
  my $err = $@;
  close STDERR or die "Cannot close captured STDERR: $!";
  open STDERR, ">&", $save or die "Cannot restore STDERR: $!";
  close $save or die "Cannot close saved STDERR: $!";
  die $err if $err;
  $stderr
}

sub has_file ($run) {
  grep exists $run->{$_}{"f.pl"}, qw( digests count vec )
}

sub test_changed_file () {
  my $db     = db_with(r1 => "a", r2 => "a", r3 => "a");
  my $stderr = merge_capturing($db, db_with(r4 => "b"));

  is has_file($db->{runs}{$_}), 0, "$_ loses its f.pl entries"
    for qw( r1 r2 r3 );
  is $db->{runs}{r4}{digests}{"f.pl"}, "b", "merged run is in place";
  is $db->{changed_files}{"f.pl"},     3,   "f.pl changed in three runs";
  is_deeply $db->{stale_digests}, { a => { "f.pl" => 1 } },
    "stale digest a is recorded with its file";
  my @lines = $stderr =~ /Deleting old coverage for changed file f\.pl/g;
  is @lines, 3, "one deletion line per run";
}

sub test_index_after_merge () {
  my $db = db_with(r1 => "a");
  $db->merge(db_with(r2 => "b"));
  is_deeply $db->{_digest_index}{"f.pl"}{b}, { r2 => 1 },
    "index names the merged run under its digest";
}

sub test_false_digests () {
  my $db = db_with(r1 => "", r2 => "a");
  $db->merge(db_with(r3 => "b"));
  ok has_file($db->{runs}{r1}), "a stored empty digest is left alone";

  $db = db_with(r1 => "a");
  $db->merge(db_with(r2 => undef));
  ok has_file($db->{runs}{r1}), "an undefined incoming digest changes nothing";
  ok !$db->{changed_files},     "no file is marked as changed";
}

sub test_index_dropped_on_read () {
  my $dir = File::Spec->catdir($Tmpdir, "other");
  db_with(r5 => "c")->write($dir);

  my $db = db_with(r1 => "a");
  $db->merge(db_with(r2 => "a"));
  $db->read(File::Spec->catfile($dir, "cover.15"));
  $db->merge(db_with(r6 => "d"));
  is has_file($db->{runs}{r5}), 0, "run read from file loses its f.pl entries";
}

sub main () {
  local $Devel::Cover::Silent = 1;
  test_changed_file;
  test_index_after_merge;
  test_false_digests;
  test_index_dropped_on_read;
}

main;
done_testing;

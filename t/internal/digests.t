#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# Digests caches digest-to-canonical-filename mappings in the digests file.
# The file is only an optimisation, so an unreadable one must not kill the
# covered run - reads warn, continue with an empty cache, and self-heal.

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
use Test::More import => [qw( done_testing is is_deeply like ok )];

use Devel::Cover::DB::Digests ();

my $Tmpdir = tempdir(CLEANUP => 1);

{
  no feature "signatures";

  sub capture_stderr (&) {
    my ($code) = @_;
    my $stderr = "";
    open my $save, ">&", \*STDERR or die "Cannot dup STDERR: $!";
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">", \$stderr or die "Cannot redirect STDERR: $!";
    $code->();
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">&", $save or die "Cannot restore STDERR: $!";
    $stderr
  }
}

sub fresh_db ($label) {
  my $db = File::Spec->catdir($Tmpdir, $label);
  make_path($db);
  $db
}

sub corrupt_digests_file ($db) {
  my $path = File::Spec->catfile($db, "digests");
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh "this is not valid serialised data";
  close $fh or die "Cannot close $path: $!";
  $path
}

sub test_new_no_db () {
  my $err = do {
    local $@;
    eval { Devel::Cover::DB::Digests->new; 1 } ? "" : $@
  };
  like $err, qr/No db specified/, "new: dies without a db";
}

sub test_round_trip () {
  my $db = fresh_db("round_trip");

  my $digests = Devel::Cover::DB::Digests->new(db => $db);
  $digests->set("file.pm", "abc123");
  $digests->write;

  my $fresh = Devel::Cover::DB::Digests->new(db => $db);
  is $fresh->get("abc123"), "file.pm", "round trip: mapping survives";
}

sub test_corrupt_read () {
  my $db = fresh_db("corrupt");
  corrupt_digests_file($db);

  my ($digests, $err);
  my $stderr = capture_stderr {
    local $@;
    $err
      = eval { $digests = Devel::Cover::DB::Digests->new(db => $db); 1 }
      ? ""
      : $@;
  };

  is $err, "", "corrupt read: survives an unreadable digests file";
  is_deeply $digests && $digests->{digests}, {},
    "corrupt read: continues with an empty cache";
  like $stderr, qr/Ignoring unreadable digests file/,
    "corrupt read: warns about the file";
}

sub test_corrupt_read_silent () {
  my $db = fresh_db("corrupt_silent");
  corrupt_digests_file($db);

  my $ok;
  my $stderr = do {
    local $Devel::Cover::Silent = 1;
    capture_stderr {
      $ok = eval { Devel::Cover::DB::Digests->new(db => $db); 1 };
    };
  };

  ok $ok, "corrupt read: survives when silent";
  is $stderr, "", "corrupt read: no warning when silent";
}

sub test_corrupt_self_heals () {
  my $db = fresh_db("self_heal");
  corrupt_digests_file($db);

  my $digests;
  my $stderr = capture_stderr {
    my $ok = eval { $digests = Devel::Cover::DB::Digests->new(db => $db); 1 };
  };
  ok $digests, "self heal: object created despite corrupt file";
  return unless $digests;

  $digests->set("healed.pm", "feedbeef");
  $digests->write;

  my $fresh = Devel::Cover::DB::Digests->new(db => $db);
  is $fresh->get("feedbeef"), "healed.pm",
    "self heal: rewritten file reads back cleanly";
}

sub main () {
  test_new_no_db;
  test_round_trip;
  test_corrupt_read;
  test_corrupt_read_silent;
  test_corrupt_self_heals;
}

main;
done_testing;

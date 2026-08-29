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

use Config     qw( %Config );
use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is isnt like plan )];

if ($^O eq "MSWin32") {
  plan skip_all => "utils/create_gold relies on fork and signals";
}

chdir "$FindBin::Bin/../.." or die "Can't chdir to the project root: $!";

my $Fixtures = tempdir(DIR => "t", CLEANUP => 1);

sub write_fixture ($name, $body) {
  my $path = "$Fixtures/$name";
  open my $fh, ">", $path or die "Can't write $path: $!";
  print $fh $body;
  close $fh or die "Can't close $path: $!";
  $path
}

sub run_create_gold (@args) {
  my $cmd = join " ", $^X, "utils/create_gold", @args;
  my $out = `$cmd 2>&1`;
  ($out, $? >> 8)
}

sub test_threaded_run_writes_nothing () {
  my ($out, $exit) = run_create_gold("unused");
  is $exit, 0, "a threaded run exits 0";
  like $out, qr/no golden results/, "the threaded run says nothing was written";
}

sub test_dying_child_exits_nonzero () {
  my $path = write_fixture("dies.pl", qq(die "broken fixture";\n));
  my ($out, $exit) = run_create_gold($path);
  isnt $exit, 0, "a dying child makes create_gold exit non-zero";
  like $out, qr/\Q$path\E failed: exited 255/, "the failing test is named";
}

sub test_signalled_child_is_reported () {
  my $path = write_fixture("signalled.pl", qq(kill "KILL", \$\$;\nsleep 5;\n));
  my ($out, $exit) = run_create_gold($path);
  isnt $exit, 0, "a signalled child makes create_gold exit non-zero";
  like $out, qr/killed by signal 9/, "the signal is reported";
}

sub test_successful_run_exits_zero () {
  my $path = write_fixture("works.pl",
        qq(package FakeGoldTest;\n)
      . qq(sub create_gold { 1 }\n)
      . qq(bless {}, "FakeGoldTest"\n));
  my ($out, $exit) = run_create_gold($path);
  is $exit, 0, "a successful run exits 0";
}

sub main () {
  if ($Config{useithreads}) {
    test_threaded_run_writes_nothing;
  } else {
    test_dying_child_exits_nonzero;
    test_signalled_child_is_reported;
    test_successful_run_exits_zero;
  }
  done_testing;
}

main

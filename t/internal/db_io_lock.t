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
use Test::More import => [qw( cmp_ok diag done_testing like plan )];

BEGIN {
  plan skip_all => "flock is emulated on Windows" if $^O eq "MSWin32";
}

sub setup ($tmpdir) {
  my $script = File::Spec->catfile($tmpdir, "lock.pl");
  open my $fh, ">", $script or die "write $script: $!";
  print $fh <<'PERL';
use Fcntl qw( LOCK_EX LOCK_NB );
use Devel::Cover::DB ();
use Devel::Cover::DB::IO::Base ();

my ($mode, $file) = @ARGV;
open my $fh, ">", $file or die "write $file: $!";
print $fh "data";
close $fh or die "close $file: $!";

close STDIN;
close STDOUT if $mode eq "inner_dies";

my $io   = Devel::Cover::DB::IO::Base->new;
my $lock = "$file.lock";
if ($mode eq "read") {
  $io->read_fh($file, sub { my $in = shift; local $/; <$in> });
} elsif ($mode eq "write") {
  $io->write_fh($file, sub { my $out = shift; print $out "more" });
} elsif ($mode eq "read_dies" || $mode eq "inner_dies") {
  eval { $io->read_fh($file, sub { die "boom\n" }) };
} elsif ($mode eq "write_dies") {
  eval { $io->write_fh($file, sub { die "boom\n" }) };
} elsif ($mode eq "merge_lock") {
  my $db = "$file.db";
  mkdir $db         or die "mkdir $db: $!";
  mkdir "$db/runs"  or die "mkdir $db/runs: $!";
  Devel::Cover::DB->new(db => $db)->merge_runs;
  $lock = "$db/merge.lock";
}

if ($mode eq "inner_dies") {
  open my $p0, "<", "/dev/null" or die "open /dev/null: $!";
  open my $p1, "<", "/dev/null" or die "open /dev/null: $!";
  print STDERR "$mode fds ", fileno($p0), " ", fileno($p1), "\n";
}

open my $probe, "+>>", $lock or die "open lock: $!";
my $state = flock($probe, LOCK_EX | LOCK_NB) ? "released" : "held";
print STDERR "$mode lock $state\n";
PERL
  close $fh or die "close $script: $!";
  $script
}

sub run_child ($mode) {
  my $tmpdir = tempdir(CLEANUP => 1);
  my $script = setup($tmpdir);
  my $file   = File::Spec->catfile($tmpdir, "data");
  my $cmd    = join " ", map qq("$_"), $^X, "-Mblib", $script, $mode, $file;
  `$cmd 2>&1`
}

sub test_lock_released ($mode) {
  my $output = run_child($mode);
  like $output, qr/\Q$mode lock released\E/,
    "$mode releases the lock when STDIN is closed"
    or diag $output;
}

sub test_inner_handles_released () {
  my $output = run_child("inner_dies");
  my ($fd0, $fd1) = $output =~ /inner_dies fds (\d+) (\d+)/;
  cmp_ok $fd0, "<", 2, "lock handle released after the reader dies"
    or diag $output;
  cmp_ok $fd1, "<", 2, "data handle released after the reader dies"
    or diag $output;
  like $output, qr/inner_dies lock released/,
    "inner_dies releases the lock when STDIN and STDOUT are closed"
    or diag $output;
}

sub main () {
  test_lock_released($_) for qw( read write read_dies write_dies merge_lock );
  test_inner_handles_released;
  done_testing;
}

main;

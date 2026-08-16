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
use Test::More import => [qw( diag done_testing like plan )];

BEGIN {
  plan skip_all => "flock is emulated on Windows" if $^O eq "MSWin32";
}

sub setup ($tmpdir) {
  my $script = File::Spec->catfile($tmpdir, "lock.pl");
  open my $fh, ">", $script or die "write $script: $!";
  print $fh <<'PERL';
use Fcntl qw( LOCK_EX LOCK_NB );
use Devel::Cover::DB::IO::Base ();

my ($mode, $file) = @ARGV;
open my $fh, ">", $file or die "write $file: $!";
print $fh "data";
close $fh or die "close $file: $!";

close STDIN;

my $io = Devel::Cover::DB::IO::Base->new;
if ($mode eq "read") {
  $io->read_fh($file, sub { my $in = shift; local $/; <$in> });
} else {
  $io->write_fh($file, sub { my $out = shift; print $out "more" });
}

open my $lock, "+>>", "$file.lock" or die "open lock: $!";
my $state = flock($lock, LOCK_EX | LOCK_NB) ? "released" : "held";
print "$mode lock $state\n";
PERL
  close $fh or die "close $script: $!";
  $script
}

sub test_lock_released ($mode) {
  my $tmpdir = tempdir(CLEANUP => 1);
  my $script = setup($tmpdir);

  my $file   = File::Spec->catfile($tmpdir, "data");
  my $cmd    = join " ", map qq("$_"), $^X, "-Mblib", $script, $mode, $file;
  my $output = `$cmd 2>&1`;

  like $output, qr/\Q$mode lock released\E/,
    "$mode releases the lock when STDIN is closed"
    or diag $output;
}

sub main () {
  test_lock_released("read");
  test_lock_released("write");
  done_testing;
}

main;

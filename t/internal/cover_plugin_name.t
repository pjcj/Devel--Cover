#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin    ();
use File::Temp qw( tempdir );

use Test::More import => [qw( done_testing like ok plan unlike )];

# cover builds a report or annotation class name from the -report and
# -annotation arguments and loads it through a string eval.  A name that is
# not a plain word must be rejected before it reaches the eval, so a mistyped
# argument gives a clear message rather than a confusing compile error.

my $Root  = "$FindBin::Bin/../..";
my $Cover = "$Root/bin/cover";
my $Lib   = "$Root/lib";

sub run_cover (@args) {
  my $tmp = tempdir(CLEANUP => 1);
  my $log = "$tmp/output";
  my $pid = fork // die "Can't fork: $!";
  if (!$pid) {
    chdir $tmp or die "chdir $tmp: $!";
    open STDOUT, ">",  $log   or die "Can't write $log: $!";
    open STDERR, ">&", STDOUT or die "Can't dup stdout: $!";
    exec $^X, "-I$Lib", $Cover, @args;
    die "Can't exec cover: $!";
  }
  waitpid $pid, 0;
  open my $fh, "<", $log or die "Can't read $log: $!";
  my $out = do { local $/; <$fh> };
  close $fh or die "Can't close $log: $!";
  { out => $out, dir => $tmp }
}

sub main () {
  my $report = run_cover("-report", 'html; open my $f, ">", "CREATED"; 1');
  ok !-e "$report->{dir}/CREATED",
    "-report does not evaluate its argument";
  like $report->{out}, qr/not a recognised output format/,
    "-report rejects an invalid format name";

  my $valid = run_cover("-report", "Text");
  unlike $valid->{out}, qr/not a recognised output format/,
    "-report still accepts a valid format name";

  my $ann = run_cover(
    "-report",     "Text",
    "-annotation", 'git; open my $f, ">", "CREATED"; 1',
  );
  ok !-e "$ann->{dir}/CREATED",
    "-annotation does not evaluate its argument";

  done_testing;
}

main;

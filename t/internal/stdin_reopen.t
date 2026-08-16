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
use Test::More import => [qw( diag done_testing like )];

sub write_file ($file, $contents) {
  open my $fh, ">", $file or die "write $file: $!";
  print $fh $contents;
  close $fh or die "close $file: $!";
}

sub test_readline_after_reopening_stdin () {
  my $tmpdir = tempdir(CLEANUP => 1);

  # Loading our own file means exactly one new file is digested
  my $trigger = File::Spec->catfile($tmpdir, "trigger.pl");
  write_file($trigger, "my \$loaded = 1;\n1;\n");
  $trigger =~ s|\\|/|g;

  my $source = <<'PERL';
close STDIN;
require "TRIGGER";
my $data = "-world-";
open STDIN, "<", \$data or die "open STDIN: $!";
my $line = <>;
print "got(", defined $line ? $line : "UNDEF", ")\n";
PERL
  $source =~ s|TRIGGER|$trigger|;

  my $script = File::Spec->catfile($tmpdir, "stdin.pl");
  write_file($script, $source);

  my $db  = File::Spec->catdir($tmpdir, "cover_db");
  my $cmd = join " ", map qq("$_"), $^X, "-Mblib",
    "-MDevel::Cover=-silent,1,-db,$db", $script;
  my $output = `$cmd 2>&1`;

  like $output, qr/\Qgot(-world-)\E/, "<> reads a reopened STDIN under coverage"
    or diag $output;
}

sub main () {
  test_readline_after_reopening_stdin;
  done_testing;
}

main;

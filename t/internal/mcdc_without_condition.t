#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# MC/DC is derived from condition truth tables, so selecting mcdc without
# condition collects nothing.  Devel::Cover must warn at startup so the
# empty report is not a mystery.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing like unlike )];

use File::Spec ();
use File::Temp qw( tempdir );

use Devel::Cover::Test::Internal qw( write_script );

my $Tmpdir  = tempdir(CLEANUP => 1);
my $Warning = qr/Devel::Cover: mcdc coverage requires condition coverage/;

sub run_covered ($label, @parts) {
  my $script  = write_script("$label.pl", 'my $r = 1 && 0;' . "\n");
  my $db      = File::Spec->catdir($Tmpdir, "db_$label");
  my $errfile = File::Spec->catfile($Tmpdir, "err_$label");
  my $devnull = File::Spec->devnull;
  my $cmd     = join " ", $^X, "-Iblib/lib", "-Iblib/arch",
    "-MDevel::Cover=" . join(",", "-db,$db", @parts), $script, ">$devnull",
    "2>$errfile";

  system($cmd) == 0 or die "Failed to run: $cmd";
  open my $fh, "<", $errfile or die "Cannot read $errfile: $!";
  my $err = do { local $/; <$fh> };
  close $fh or die "Cannot close $errfile: $!";
  $err
}

like run_covered("mcdc_only", "-coverage,mcdc"), $Warning,
  "mcdc without condition warns at startup";

unlike run_covered("mcdc_and_condition", "-coverage,condition,mcdc"), $Warning,
  "mcdc with condition does not warn";

unlike run_covered("default_set"), $Warning,
  "the default coverage set does not warn";

unlike run_covered("mcdc_only_silent", "-coverage,mcdc", "-silent,1"),
  $Warning, "-silent suppresses the warning";

done_testing;

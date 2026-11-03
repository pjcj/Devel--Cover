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
use Test::More import => [qw( diag done_testing is like plan unlike )];
use Devel::Cover::Test::Showcase qw( run_cover );

sub write_program ($tmpdir) {
  my $program = File::Spec->catfile($tmpdir, "separators.pl");
  open my $fh, ">", $program or die "Cannot write $program: $!";
  print $fh <<'PERL' =~ s/^  //gmr;
  $\ = "|";
  print "a", "b";
PERL
  close $fh or die "Cannot close $program: $!";
  $program
}

sub run_program ($tmpdir, $program) {
  my $db = File::Spec->catdir($tmpdir, "cover_db");
  local $ENV{DEVEL_COVER_DB_FORMAT} = "JSON";
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch"
    . " -MDevel::Cover=-db,$db,-silent,1,-merge,0,-select,separators"
    . " $program 2>&1";
  my $out = `$cmd`;
  is $? >> 8, 0,     "program exits 0" or diag $out;
  is $out,    "ab|", "program prints with its separators";
  $db
}

sub test_report ($db) {
  my ($out, $exit) = run_cover("-report", "text", $db);
  is $exit, 0, "text report exits 0" or diag $out;
  unlike $out, qr/Can't read/,              "text report reads every file";
  like $out,   qr/separators\.pl\s+100\.0/, "text report covers the program";
}

sub main () {
  plan skip_all => "needs JSON::MaybeXS" unless eval { require JSON::MaybeXS };
  my $tmpdir  = tempdir(CLEANUP => 1);
  my $program = write_program($tmpdir);
  my $db      = run_program($tmpdir, $program);
  test_report($db);
  done_testing;
}

main;

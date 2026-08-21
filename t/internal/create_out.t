#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# create_out writes the cover output for a test to a file, normalised the
# same way create_gold normalises golden results, so make diff can compare
# the two byte for byte.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", qw( ./lib ./blib/lib ./blib/arch ./t );

use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is ok )];

use Devel::Cover::Test ();

my $Dir = tempdir(CLEANUP => 1);

sub write_fake_cover () {
  my $path = "$Dir/fake_cover";
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh <<'PERL';
print "cover: merging 1 and 2\n";
print "cover: Reading database from /tmp/cover_db\n";
print "Run: tests/foo\n";
print "Perl version: 5.44.0\n";
print "OS: darwin\n";
print "Start: Tue Aug 18 15:00:00 2026\n";
print "Finish: Tue Aug 18 15:00:01 2026\n";
print "Total 100.0\n";
PERL
  close $fh or die "Cannot close $path: $!";
  $path
}

sub read_file ($file) {
  open my $fh, "<", $file or die "Cannot open $file: $!";
  local $/;
  <$fh>
}

sub main () {
  my $fake = write_fake_cover;
  my $test
    = Devel::Cover::Test->new("create_out_selftest", run_test => sub { });

  ok $test->can("create_out"), "create_out exists";

  my $out = "$Dir/selftest.out";
  {
    no warnings "redefine";
    local *Devel::Cover::Test::cover_command = sub ($self) {
      qq($^X "$fake")
    };
    $test->create_out($out);
  }

  is read_file($out), <<'TEXT', "output is normalised like a golden file";
cover: Reading database from ...
Run: ...
Perl version: ...
OS: ...
Start: ...
Finish: ...
Total 100.0
TEXT

  rmdir "./t/e2e/cover_db_create_out_selftest";
}

main;
done_testing;

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();  ## no perlimports
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Cwd        qw( getcwd );
use File::Path qw( make_path );
use File::Temp qw( tempdir );

use Test::More import => [qw( done_testing is like ok plan )];

BEGIN {
  plan skip_all => "Devel::Cover::Collection requires Perl 5.42" if $] < 5.042;
  plan skip_all => "Devel::Cover::Collection is not portable to Windows"
    if $^O eq "MSWin32";
  for my $module (qw( Template Parallel::Iterator JSON::MaybeXS )) {
    plan skip_all => "$module required for this test"
      unless eval "require $module; 1";
  }
}

use Devel::Cover::Collection ();

my $Tmp       = tempdir CLEANUP => 1;
my $Bin       = "$Tmp/bin";
my $Build_dir = "$Tmp/build/My-Module-1.02-1234";
make_path $Bin, $Build_dir;

# A fake cover: --test leaves a valid cover_db but reports failing tests,
# any report run succeeds and records that it happened
open my $fh, ">", "$Bin/cover" or die "Can't open $Bin/cover: $!";
print $fh <<'EOS';
use strict;
use warnings;
if (grep $_ eq "--test", @ARGV) {
  mkdir "cover_db" or die "Can't mkdir cover_db: $!";
  open my $fh, ">", "cover_db/marker" or die "Can't open marker: $!";
  print $fh "coverage\n";
  close $fh or die "Can't close marker: $!";
  print "Result: FAIL\n";
  exit 3;
}
open my $fh, ">", "cover_db/report_generated" or die "Can't open report: $!";
close $fh or die "Can't close report: $!";
exit 0;
EOS
close $fh or die "Can't close $Bin/cover: $!";

my $Collection = Devel::Cover::Collection->new(
  bin_dir     => $Bin,
  results_dir => "$Tmp/results",
);

my @Warnings;
local $SIG{__WARN__} = sub { push @Warnings, @_ };

my $Cwd = getcwd;
open my $Saved_stdout, ">&", \*STDOUT       or die "Can't save STDOUT: $!";
open STDOUT,           ">",  "$Tmp/run.out" or die "Can't redirect STDOUT: $!";
my $Err = do { local $@; eval { $Collection->run($Build_dir) }; $@ };
open STDOUT, ">&", $Saved_stdout or die "Can't restore STDOUT: $!";
chdir $Cwd or die "Can't chdir $Cwd: $!";

my $Rdir = "$Tmp/results/My-Module-1.02";
is $Err, "", "run survives a failing test suite";
ok -e "$Rdir/marker",           "coverage database is published";
ok -e "$Rdir/report_generated", "report generation still runs";
like join("", @Warnings), qr/exit 3/, "test failure is still warned";

done_testing;

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

my $Tmp = tempdir CLEANUP => 1;
my $Bin = "$Tmp/bin";
make_path $Bin;

# A fake cover: records its arguments, --test leaves a valid cover_db but
# reports failing tests, any report run succeeds and records that it
# happened, or fails when FAKE_COVER_FAIL_REPORT is set
open my $Fh, ">", "$Bin/cover" or die "Can't open $Bin/cover: $!";
print $Fh <<'EOS';
use strict;
use warnings;
open my $afh, ">>", "cover_args" or die "Can't open cover_args: $!";
print $afh "@ARGV\n";
close $afh or die "Can't close cover_args: $!";
if (grep $_ eq "--test", @ARGV) {
  mkdir "cover_db" or die "Can't mkdir cover_db: $!";
  open my $mfh, ">", "cover_db/marker" or die "Can't open marker: $!";
  print $mfh "coverage\n";
  close $mfh or die "Can't close marker: $!";
  print "Result: FAIL\n";
  exit 3;
}
exit 1 if $ENV{FAKE_COVER_FAIL_REPORT};
open my $rfh, ">", "cover_db/report_generated" or die "Can't open report: $!";
close $rfh or die "Can't close report: $!";
exit 0;
EOS
close $Fh or die "Can't close $Bin/cover: $!";

sub slurp ($path) {
  open my $fh, "<", $path or die "Can't open $path: $!";
  my $content = do { local $/; <$fh> };
  close $fh or die "Can't close $path: $!";
  $content
}

my $N = 0;

sub run_scenario (%opt) {
  my $n         = ++$N;
  my $build_dir = "$Tmp/build$n/My-Module-1.02-1234";
  make_path $build_dir;
  make_path "$build_dir/$_" for ($opt{dirs} // [])->@*;

  my $collection = Devel::Cover::Collection->new(
    bin_dir     => $Bin,
    results_dir => "$Tmp/results$n",
  );

  my @warnings;
  local $SIG{__WARN__}               = sub { push @warnings, @_ };
  local $ENV{FAKE_COVER_FAIL_REPORT} = $opt{fail_report} // "";

  my $cwd = getcwd;

  open my $saved_stdout, ">&", \*STDOUT or die "Can't save STDOUT: $!";
  open STDOUT, ">", "$Tmp/run$n.out"    or die "Can't redirect STDOUT: $!";
  my $err = do { local $@; eval { $collection->run($build_dir) }; $@ };
  open STDOUT, ">&", $saved_stdout or die "Can't restore STDOUT: $!";
  chdir $cwd or die "Can't chdir $cwd: $!";

  my $args = "$build_dir/cover_args";
  {
    err      => $err,
    stdout   => slurp("$Tmp/run$n.out"),
    args     => -e $args ? slurp($args) : "",
    warnings => join("", @warnings),
    rdir     => "$Tmp/results$n/My-Module-1.02",
  }
}

sub test_failing_tests_still_publish () {
  my $r = run_scenario(dirs => ["blib", "lib"]);
  is $r->{err}, "", "run survives a failing test suite";
  ok -e "$r->{rdir}/marker",           "coverage database is published";
  ok -e "$r->{rdir}/report_generated", "report generation still runs";
  like $r->{warnings}, qr/exit 3/,              "test failure is still warned";
  like $r->{args},     qr/--select_dir blib\b/, "blib preferred as select_dir";
}

sub test_select_dir_fallbacks () {
  my $r = run_scenario(dirs => ["lib"]);
  like $r->{args}, qr/--select_dir lib\b/, "lib used when blib is absent";

  $r = run_scenario;
  like $r->{args}, qr/--select_dir \./, "current dir used as last resort";
}

sub test_log_survives_report_failure () {
  my $r = run_scenario(dirs => ["lib"], fail_report => 1);
  like $r->{err},    qr/Can't run/,         "report failure propagates";
  like $r->{stdout}, qr/Testing My-Module/, "collected output is still printed";
  like $r->{stdout}, qr/json_summary/,      "report command is logged";
}

test_failing_tests_still_publish;
test_select_dir_fallbacks;
test_log_survives_report_failure;

done_testing;

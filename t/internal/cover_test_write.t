#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Config     qw( %Config );
use Cwd        qw( getcwd );
use File::Spec ();
use File::Temp qw( tempdir );

use Test::More import => [qw( done_testing is like note ok plan unlike )];

if ($^O eq "MSWin32") {
  plan skip_all => "test drives make with a stub Makefile";
  exit;
}

my $Project   = getcwd;
my $Cover     = File::Spec->catfile($Project, "bin", "cover");
my $Blib_lib  = File::Spec->catdir($Project, "blib", "lib");
my $Blib_arch = File::Spec->catdir($Project, "blib", "arch");
my $Make      = $Config{make};

unless (-f $Cover && -d $Blib_lib && -d $Blib_arch) {
  plan skip_all => "build artefacts missing - run after `make`";
  exit;
}

if (system "command -v $Make >/dev/null 2>&1") {
  plan skip_all => "$Make not available";
  exit;
}

sub write_makefile ($dir) {
  my $makefile = File::Spec->catfile($dir, "Makefile");
  open my $fh, ">", $makefile or die "open $makefile: $!";
  print $fh "test:\n\t\@'$^X' -e 'my \$\$x = 1'\n";
  close $fh or die "close $makefile: $!";
}

sub run_cover ($dir, @args) {
  my $args = join " ", map "'$_'", @args;
  my $out  = `cd '$dir' && '$^X' '$Cover' -test -nogcov $args 2>&1`;
  note $out;
  ($? >> 8, $out)
}

sub test_write_generates_no_report () {
  my $dir = tempdir(CLEANUP => 1);
  write_makefile($dir);
  my ($rc, $out) = run_cover($dir, "-write", "mydb");
  is $rc, 0, "cover -test -write exits with the test status";
  unlike $out, qr/Can't locate object method/, "no unloaded report crash";
  ok -e File::Spec->catfile($dir, "mydb", "cover.15"), "database written";
  my @html = glob File::Spec->catfile($dir, "cover_db", "*.html");
  is @html, 0, "no report generated";
}

sub test_write_with_explicit_report () {
  my $dir = tempdir(CLEANUP => 1);
  write_makefile($dir);
  my ($rc, $out) = run_cover($dir, "-write", "mydb", "-report", "text");
  is $rc, 0, "cover -test -write -report text exits with the test status";
  like $out, qr/^Run: +-e$/m, "explicit report still generated";
}

sub test_write_with_invalid_report () {
  my $dir = tempdir(CLEANUP => 1);
  write_makefile($dir);
  my ($rc, $out) = run_cover($dir, "-write", "mydb", "-report", "bogus");
  is $rc, 0, "cover -test -write -report bogus exits with the test status";
  like $out,   qr/not a recognised output format/, "invalid report reported";
  unlike $out, qr/Can't locate object method/,     "no unloaded report crash";
}

sub main () {
  local $ENV{PERL5LIB} = join $Config{path_sep}, $Blib_lib, $Blib_arch,
    ($ENV{PERL5LIB} // ());

  test_write_generates_no_report;
  test_write_with_explicit_report;
  test_write_with_invalid_report;
  done_testing;
}

main;

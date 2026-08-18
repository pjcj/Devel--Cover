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

use Test::More import => [qw( done_testing is like note plan unlike )];

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

sub write_file ($path, $contents) {
  open my $fh, ">", $path or die "open $path: $!";
  print $fh $contents;
  close $fh or die "close $path: $!";
}

sub write_dist ($dir) {
  write_file(
    File::Spec->catfile($dir, "Module.pm"),
    "package Module;\nsub answer { 42 }\n1;\n",
  );
  write_file(
    File::Spec->catfile($dir, "script.pl"),
    "use Module;\nModule::answer();\n",
  );
  write_file(
    File::Spec->catfile($dir, "Makefile"),
    "test:\n\t\@'$^X' -I. script.pl\n",
  );
}

sub run_cover_test ($dir, @args) {
  my $args = join " ", @args;
  my $out = `cd '$dir' && '$^X' '$Cover' -test -nogcov -report text $args 2>&1`;
  note $out;
  ($? >> 8, $out)
}

sub test_comma_regex_is_ignored () {
  my $dir = tempdir(CLEANUP => 1);
  write_dist($dir);

  my ($rc, $out) = run_cover_test($dir, "-ignore_re", "'Mod{1,1}ule'");
  is $rc, 0, "cover -test exits successfully";
  unlike $out, qr/Unescaped left brace/, "pattern arrives uncorrupted";
  unlike $out, qr/^Module\.pm\b/m,       "pattern with comma ignores the file";
}

sub test_comma_db_path () {
  my $dir = File::Spec->catdir(tempdir(CLEANUP => 1), "with,comma");
  mkdir $dir or die "mkdir $dir: $!";
  write_dist($dir);

  my ($rc, $out) = run_cover_test($dir);
  is $rc, 0, "cover -test exits successfully";
  unlike $out, qr/Unknown option|Can't stat/, "db path arrives uncorrupted";
  like $out,   qr/^Module\.pm\b/m, "coverage collected in the comma path";
}

sub main () {
  local $ENV{PERL5LIB} = join $Config{path_sep}, $Blib_lib, $Blib_arch,
    ($ENV{PERL5LIB} // ());

  test_comma_regex_is_ignored;
  test_comma_db_path;
  done_testing;
}

main;

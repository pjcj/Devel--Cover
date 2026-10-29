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
use Cwd        qw( abs_path getcwd );
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

sub write_project ($dir, $other) {
  my $path = File::Spec->catfile($dir, "script.pl");
  write_file($path, "my \$x = 1;\n");
  write_file(
    File::Spec->catfile($dir, "run_child.pl"),
    qq(chdir '$other' or die "chdir: \$!";\n)
      . qq[system(\$^X, '$path') == 0 or die "child failed: \$?";\n],
  );
  write_file(
    File::Spec->catfile($dir, "Makefile"),
    "test:\n\t\@'$^X' run_child.pl\n",
  );
  $path
}

sub run_cover ($dir) {
  my $out = `cd '$dir' && '$^X' '$Cover' -test -nogcov -report text 2>&1`;
  note $out;
  ($? >> 8, $out)
}

sub test_child_from_other_dir () {
  my $dir   = abs_path(tempdir(CLEANUP => 1));
  my $other = abs_path(tempdir(CLEANUP => 1));
  my $path  = write_project($dir, $other);
  my ($rc, $out) = run_cover($dir);
  is $rc, 0, "cover -test exits with the test status";
  like $out,   qr/^script\.pl\s/m, "a row names script.pl relative to the dir";
  unlike $out, qr/^\Q$path\E$/m,   "no line names the child file by its path";
}

sub main () {
  local $ENV{PERL5LIB} = join $Config{path_sep}, $Blib_lib, $Blib_arch,
    ($ENV{PERL5LIB} // ());

  test_child_from_other_dir;
  done_testing;
}

main;

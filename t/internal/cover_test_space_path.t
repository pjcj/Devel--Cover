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

sub write_makefile ($dir) {
  my $makefile = File::Spec->catfile($dir, "Makefile");
  open my $fh, ">", $makefile or die "open $makefile: $!";
  print $fh "test:\n\t\@'$^X' -e 'my \$\$x = 1'\n";
  close $fh or die "close $makefile: $!";
}

sub run_cover_test ($dir) {
  my $out = `cd '$dir' && '$^X' '$Cover' -test -nogcov -report text 2>&1`;
  note $out;
  ($? >> 8, $out)
}

sub test_space_path () {
  my $dir = File::Spec->catdir(tempdir(CLEANUP => 1), "with space");
  mkdir $dir or die "mkdir $dir: $!";
  write_makefile($dir);

  my ($rc, $out) = run_cover_test($dir);
  is $rc, 0, "cover -test exits successfully";
  unlike $out, qr/Illegal switch in PERL5OPT/, "no PERL5OPT switch error";
  unlike $out, qr/Can't stat/,                 "database was written and read";
  like $out,   qr/^Run: +-e$/m,                "run recorded in the database";
}

sub main () {
  local $ENV{PERL5LIB} = join $Config{path_sep}, $Blib_lib, $Blib_arch,
    ($ENV{PERL5LIB} // ());

  test_space_path;
  done_testing;
}

main;

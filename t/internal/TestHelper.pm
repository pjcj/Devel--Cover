package TestHelper;

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use v5.20.0;
use strict;
use warnings;
use feature qw( signatures );
no warnings qw( experimental::signatures );

use Exporter qw( import );
our @EXPORT_OK = qw( create_cover_db run_cover setup_lib_dir );

use Cwd            qw( realpath );
use File::Basename qw( dirname );
use File::Path     qw( make_path );
use File::Spec     ();
use File::Temp     qw( tempdir );

my $Root  = realpath(File::Spec->catdir(dirname(__FILE__), "..", ".."));
my $Cover = File::Spec->catfile($Root, "bin", "cover");

sub run_cover (@args) {
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd = join " ", "$^X -Iblib/lib -Iblib/arch", $Cover, @args;
  my $out = `$cmd 2>&1`;
  ($out, $? >> 8)
}

sub _write_module ($path, $pkg, $body) {
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh "package $pkg;\n$body\n1\n";
  close $fh or die "Cannot close $path: $!"
}

sub setup_lib_dir () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $libdir = File::Spec->catdir($tmpdir, "lib");
  make_path($libdir);

  _write_module(
    File::Spec->catfile($libdir, "Covered.pm"),
    "Covered",
    'sub hello { "hello" }'
  );
  _write_module(
    File::Spec->catfile($libdir, "Uncovered.pm"),
    "Uncovered",
    'sub world { "world" }'
  );

  # blib subdir - should be excluded by scan_select_dirs
  my $blib = File::Spec->catdir($libdir, "blib", "lib");
  make_path($blib);
  _write_module(
    File::Spec->catfile($blib, "BlibMod.pm"),
    "BlibMod", "sub x { 1 }"
  );

  # non-pm file - should be excluded
  open my $fh, ">", File::Spec->catfile($libdir, "README.txt")
    or die "Cannot create README: $!";
  close $fh or die $!;

  ($tmpdir, $libdir)
}

sub create_cover_db ($tmpdir, $libdir) {
  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  my $select   = quotemeta $libdir;

  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};

  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$libdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0,-select,$select"
    . ' -e "use Covered; Covered::hello()" 2>&1';
  my $out = `$cmd`;
  die "Failed to create cover_db:\n$out\n" if $?;

  $cover_db
}

1

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
use File::Path qw( mkpath );
use File::Spec ();
use File::Temp qw( tempdir );

use Test::More import => [qw( done_testing is note ok plan )];

if ($^O eq "MSWin32") {
  plan skip_all => "test drives a stub Build script";
  exit;
}

my $Project   = getcwd;
my $Cover     = File::Spec->catfile($Project, "bin", "cover");
my $Blib_lib  = File::Spec->catdir($Project, "blib", "lib");
my $Blib_arch = File::Spec->catdir($Project, "blib", "arch");

unless (-f $Cover && -d $Blib_lib && -d $Blib_arch) {
  plan skip_all => "build artefacts missing - run after `make`";
  exit;
}

sub write_file ($path, $contents) {
  open my $fh, ">", $path or die "open $path: $!";
  print $fh $contents;
  close $fh or die "close $path: $!";
}

sub setup_dist ($dir) {
  my $build = File::Spec->catfile($dir, "Build");
  write_file($build, <<BASH);
#!/usr/bin/env bash
printf '%s\\n' "\$@" >build.args
'$^X' -e 'my \$x = 1'
BASH
  chmod 0755, $build;

  mkpath(File::Spec->catdir($dir, "_build"));
  write_file(File::Spec->catfile($dir, "_build", "build_params"), <<'PERL');
[
  {}, {},
  {
    extra_compiler_flags => ["-DCOMPILER_ONLY"],
    extra_linker_flags   => ["-Wl,-rpath,/opt/lib"],
  },
]
PERL
}

sub run_cover ($dir) {
  my $out = `cd '$dir' && '$^X' '$Cover' -test -gcov -report text 2>&1`;
  note $out;
  ($? >> 8, $out)
}

sub build_args ($dir) {
  my $path = File::Spec->catfile($dir, "build.args");
  open my $fh, "<", $path or die "open $path: $!";
  chomp(my @args = <$fh>);
  close $fh or die "close $path: $!";
  @args
}

sub test_mb_flags () {
  my $dir = tempdir(CLEANUP => 1);
  setup_dist($dir);
  my ($rc, $out) = run_cover($dir);

  is $rc, 0, "cover -test -gcov exits successfully";

  my @args = build_args($dir);
  is $args[0], "test", "Build runs the test action";

  my ($config) = grep $args[$_] eq "--config", 0 .. $#args;
  ok defined $config, "--config is passed to Build";
  is $args[($config // -2) + 1], "optimize=-O0",
    "optimisation is set through --config so it replaces the default";

  my ($c) = grep /^--extra_compiler_flags=/, @args;
  my ($l) = grep /^--extra_linker_flags=/,   @args;
  is $c, "--extra_compiler_flags=-DCOMPILER_ONLY -fprofile-arcs "
    . "-ftest-coverage", "compiler flags hold the distribution and gcov flags";
  is $l, "--extra_linker_flags=-Wl,-rpath,/opt/lib -fprofile-arcs "
    . "-ftest-coverage", "linker flags hold only linker and gcov flags";
}

sub main () {
  local $ENV{PERL5LIB} = join $Config{path_sep}, $Blib_lib, $Blib_arch,
    ($ENV{PERL5LIB} // ());

  test_mb_flags;
  done_testing;
}

main;

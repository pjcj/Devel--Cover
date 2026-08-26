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

sub write_file ($path, $contents) {
  open my $fh, ">", $path or die "open $path: $!";
  print $fh $contents;
  close $fh or die "close $path: $!";
}

sub setup_dist ($dir) {
  write_file(
    File::Spec->catfile($dir, "Makefile"),
    "test:\n\t\@'$^X' -e 'my \$\$x = 1'\n",
  );
  write_file(File::Spec->catfile($dir, "Top.xs"),   "int top_line;\n");
  write_file(File::Spec->catfile($dir, "Top.gcno"), "Top.xs\n");
  my $deep = File::Spec->catdir($dir, "lib", "Deep");
  mkpath $deep;
  write_file(File::Spec->catfile($deep, "Thing.xs"),   "int deep_line;\n");
  write_file(File::Spec->catfile($deep, "Thing.gcno"), "lib/Deep/Thing.xs\n");

  # a distribution built in its own directory, as under tmp/runs
  my $foreign = File::Spec->catdir($dir, "foreign");
  mkpath $foreign;
  write_file(File::Spec->catfile($foreign, "Alien.xs"),   "int alien_line;\n");
  write_file(File::Spec->catfile($foreign, "Alien.gcno"), "Alien.xs\n");

  # the same, but recognisable as a separate build from its build files
  my $bundled = File::Spec->catdir($dir, "bundled");
  mkpath $bundled;
  write_file(File::Spec->catfile($bundled, "Makefile"),   "test:\n");
  write_file(File::Spec->catfile($bundled, "Inner.xs"),   "int inner_line;\n");
  write_file(File::Spec->catfile($bundled, "Inner.gcno"), "Inner.xs\n");
}

# each .gcno fixture holds the compiler-recorded source name gcov works from
sub write_fake_gcov ($dir) {
  my $fakebin = File::Spec->catdir($dir, "fakebin");
  mkpath $fakebin;
  my $gcov = File::Spec->catfile($fakebin, "gcov");
  write_file($gcov, <<'BASH');
#!/usr/bin/env bash

set -eEuo pipefail
# inherit_errexit needs bash 4.4, newer than the macOS system bash
shopt -s inherit_errexit 2>/dev/null || true

echo "$@" >>gcov.args
obj_dir=.
mangle=false
prev=
src=
for arg; do
  if [[ $prev == -o ]]; then obj_dir=$arg; fi
  if [[ $arg == -[!-]*p* ]]; then mangle=true; fi
  prev=$arg
  src=$arg
done
base=$(basename "$src")
gcno=$obj_dir/${base%.*}.gcno
recorded=$(cat "$gcno")
if [[ $mangle == true ]]; then
  out=${recorded//\//#}.gcov
else
  out=$(basename "$recorded").gcov
fi
headers() {
  printf '        -:    0:Source:%s\n' "$recorded"
  printf '        -:    0:Graph:%s\n' "$gcno"
  printf '        -:    0:Data:%s\n' "${gcno%.gcno}.gcda"
  printf '        -:    0:Runs:1\n'
}
# FAKE_GCOV_STUBS gives Apple-style header-only stubs for unreadable sources
if [[ -r $recorded ]]; then
  text=$(cat "$recorded")
elif [[ ${FAKE_GCOV_STUBS:-} ]]; then
  text=
else
  text='/*EOF*/'
fi
headers >"$out"
if [[ $text ]]; then
  printf '        1:    1:%s\n' "$text" >>"$out"
fi
echo "Creating '$out'"
BASH
  chmod 0755, $gcov;
  $fakebin
}

sub run_cover ($dir, $fakebin, @extra) {
  my $opts = join " ", "-test", "-gcov", @extra, "-report", "text";
  my $cmd
    = qq(cd '$dir' && PATH='$fakebin':"\$PATH" ) . "'$^X' '$Cover' $opts 2>&1";
  my $out = `$cmd`;
  note $out;
  ($? >> 8, $out)
}

sub gcov_args ($dir) {
  my $path = File::Spec->catfile($dir, "gcov.args");
  return "" unless -e $path;
  open my $fh, "<", $path or die "open $path: $!";
  local $/;
  my $args = <$fh>;
  close $fh or die "close $path: $!";
  $args
}

sub test_default_mode () {
  my $dir = tempdir(CLEANUP => 1);
  setup_dist($dir);
  my $fakebin = write_fake_gcov($dir);
  my ($rc, $out) = run_cover($dir, $fakebin);

  is $rc, 0, "cover -test -gcov exits successfully";

  my $args = gcov_args($dir);
  like $args, qr|^-\S*p\S* -o lib/Deep lib/Deep/Thing\.xs$|m,
    "gcov runs for the subdirectory XS with its path and -p";
  like $args, qr/^-\S*p\S* -o \. Top\.xs$/m, "gcov runs for the top-level XS";

  like $out, qr|lib/Deep/Thing\.xs\s+100\.0|,
    "subdirectory XS has statement coverage in the report";
  like $out, qr/Top\.xs\s+100\.0/, "top-level XS has statement coverage";

  ok !-e File::Spec->catfile($dir, "Alien.xs.gcov"),
    "stub .gcov from a foreign build is removed";
  unlike $out,  qr/Alien\.xs\s+\d/, "foreign build does not reach the report";
  unlike $args, qr/Inner/,          "no gcov run inside a bundled build";
}

# under -gcov_chdir the recorded source stays relative to the build root
sub test_gcov_chdir () {
  my $dir = tempdir(CLEANUP => 1);
  setup_dist($dir);
  my $fakebin = write_fake_gcov($dir);
  my ($rc, $out) = run_cover($dir, $fakebin, "-gcov_chdir");

  is $rc, 0, "cover -test -gcov -gcov_chdir exits successfully";

  like gcov_args(File::Spec->catdir($dir, "lib", "Deep")),
    qr/^-\S*p\S* Thing\.xs$/m, "gcov runs inside the subdirectory without -o";

  like $out, qr|lib/Deep/Thing\.xs\s+100\.0|,
    "subdirectory XS has statement coverage in the report";
  like $out, qr/Top\.xs\s+100\.0/, "top-level XS has statement coverage";
  like $out, qr|foreign/Alien\.xs\s+100\.0|,
    "separate build is covered under -gcov_chdir";
}

# a root-compiled subdirectory XS gives a header-only stub under -gcov_chdir
sub test_gcov_chdir_stub () {
  my $dir = tempdir(CLEANUP => 1);
  setup_dist($dir);
  my $fakebin = write_fake_gcov($dir);
  local $ENV{FAKE_GCOV_STUBS} = 1;
  my ($rc, $out) = run_cover($dir, $fakebin, "-gcov_chdir");

  is $rc, 0, "cover exits successfully when stubs are discarded";
  unlike $out, qr|lib/Deep/Thing\.xs\s+\d|,
    "header-only stub does not reach the report";
  like $out, qr/discarding/, "stub discard is reported";
  ok !-e File::Spec->catfile($dir, "lib", "Deep", "lib#Deep#Thing.xs.gcov"),
    "stub .gcov is removed";
}

sub main () {
  local $ENV{PERL5LIB} = join $Config{path_sep}, $Blib_lib, $Blib_arch,
    ($ENV{PERL5LIB} // ());

  test_default_mode;
  test_gcov_chdir;
  test_gcov_chdir_stub;

  done_testing;
}

main;

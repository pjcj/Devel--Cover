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

use File::Path qw( make_path );
use File::Temp ();
use Test::More import => [qw( done_testing is like ok plan subtest unlike )];

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

sub write_file ($path, $content) {
  open my $fh, ">", $path or die "Can't open $path: $!";
  print $fh $content;
  close $fh or die "Can't close $path: $!";
}

sub slurp ($path) {
  open my $fh, "<", $path or die "Can't open $path: $!";
  local $/;
  my $content = <$fh>;
  close $fh or die "Can't close $path: $!";
  $content
}

# cover_modules runs "utils/dc ... cpancover-docker-module <module> <name>"
# relative to the cwd, so chdir to a scratch project dir holding a stub dc
# that logs each call and creates the distdir a real build would produce.
my $Proj = File::Temp->newdir;
my $Perl = $^X;

make_path("$Proj/utils");
write_file("$Proj/utils/dc", <<EOS);
#!$Perl
my \$results_dir;
for my \$i (0 .. \$#ARGV) {
  \$results_dir = \$ARGV[\$i + 1] if \$ARGV[\$i] eq "--results_dir";
}
my \$module = \$ARGV[-2];
(my \$dist = \$module) =~ s|.*/||;
\$dist =~ s/\\.(?:zip|tgz|tar\\.(?:gz|bz2|xz))\$//;
open my \$fh, ">>", \$ENV{STUB_LOG} or die "Can't open \$ENV{STUB_LOG}: \$!";
print \$fh "\$module rebuild=", \$ENV{CPANCOVER_REBUILD} // "", "\\n";
close \$fh or die "Can't close \$ENV{STUB_LOG}: \$!";
mkdir "\$results_dir/\$dist" or die "Can't mkdir \$results_dir/\$dist: \$!";
open \$fh, ">", "\$results_dir/\$dist/cover.json" or die "Can't open: \$!";
print \$fh "{}";
close \$fh or die "Can't close: \$!";
EOS
chmod 0755, "$Proj/utils/dc" or die "Can't chmod $Proj/utils/dc: $!";

chdir "$Proj" or die "Can't chdir $Proj: $!";
END { chdir "/" }  # let File::Temp remove $Proj

delete $ENV{CPANCOVER_REBUILD};

my $Covered = "X/YZ/XYZ/Foo-Bar-1.00.tar.gz";
my $New     = "X/YZ/XYZ/Baz-Qux-2.00.tar.gz";

sub new_results_dir {
  my $dir = File::Temp->newdir;
  make_path("$dir/Foo-Bar-1.00");
  write_file("$dir/Foo-Bar-1.00/cover.json", "{}");
  $dir
}

sub newcp ($results_dir, %opts) {
  Devel::Cover::Collection->new(
    results_dir => "$results_dir",
    env         => "dev",
    modules     => [],
    workers     => 0,
    timeout     => 30,
    %opts,
  )
}

subtest "mark_rebuilt skips covered dists and marks new builds" => sub {
  my $dir = new_results_dir;
  my $log = "$dir/calls.log";
  local $ENV{STUB_LOG} = $log;
  write_file($log, "");

  my $cp = newcp($dir, mark_rebuilt => 1);
  $cp->set_modules($Covered, $New);
  my $built = $cp->cover_modules;

  my $calls = slurp($log);
  unlike $calls, qr/Foo-Bar/, "covered dist is not rebuilt";
  like $calls,   qr/Baz-Qux/, "new dist is built";
  unlike $calls, qr/Baz-Qux\S* rebuild=1/,
    "new dist is built without CPANCOVER_REBUILD";
  ok !-e "$dir/__rebuilt__/Foo-Bar-1.00", "covered dist gets no marker";
  ok -e "$dir/__rebuilt__/Baz-Qux-2.00",  "new dist is marked rebuilt";
  is $built, 1, "cover_modules reports one build";
};

subtest "plain build counts builds and writes no markers" => sub {
  my $dir = new_results_dir;
  my $log = "$dir/calls.log";
  local $ENV{STUB_LOG} = $log;
  write_file($log, "");

  my $cp = newcp($dir);
  $cp->set_modules($Covered, $New);
  my $built = $cp->cover_modules;

  my $calls = slurp($log);
  unlike $calls, qr/Foo-Bar/, "covered dist is not rebuilt";
  like $calls,   qr/Baz-Qux/, "new dist is built";
  ok !-e "$dir/__rebuilt__/Baz-Qux-2.00", "no marker without mark_rebuilt";
  is $built, 1, "cover_modules reports one build";
};

subtest "rebuild mode rebuilds covered dists with CPANCOVER_REBUILD" => sub {
  my $dir = new_results_dir;
  my $log = "$dir/calls.log";
  local $ENV{STUB_LOG} = $log;
  write_file($log, "");

  my $cp = newcp($dir, rebuild => 1);
  $cp->set_modules($Covered);
  my $built = $cp->cover_modules;

  like slurp($log), qr/Foo-Bar\S* rebuild=1/,
    "covered dist is rebuilt with CPANCOVER_REBUILD set";
  ok -e "$dir/__rebuilt__/Foo-Bar-1.00", "rebuilt dist is marked";
  is $built, 1, "cover_modules reports one build";
};

done_testing;

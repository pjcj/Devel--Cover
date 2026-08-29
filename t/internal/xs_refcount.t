#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Cwd        qw( getcwd );
use File::Spec ();
use File::Temp qw( tempdir );

use Test::More import => [qw( done_testing is like note plan )];

my $Project   = getcwd;
my $Blib_lib  = File::Spec->catdir($Project, "blib", "lib");
my $Blib_arch = File::Spec->catdir($Project, "blib", "arch");

unless (-d $Blib_lib && -d $Blib_arch) {
  plan skip_all => "build artefacts missing - run after `make`";
  exit;
}

my $Fixture = <<'PERL';
my $x = 1;
my $y = 0;
my $r = $x && $y ? 1 : 2;
require TestMod;
require B;
my $c = Devel::Cover::coverage(0);
my @out;
for my $crit (qw( branch condition module )) {
  my $h = $c->{$crit};
  next unless ref $h eq "HASH";
  my ($k) = sort grep ref $h->{$_} eq "ARRAY", keys %$h;
  next unless defined $k;
  push @out, "$crit=" . B::svref_2object($h->{$k})->REFCNT;
}
my $plain = { k => [ 1, 2 ] };
push @out, "baseline=" . B::svref_2object($plain->{k})->REFCNT;
print join ",", @out;
PERL

sub run_fixture () {
  my $dir     = tempdir(CLEANUP => 1);
  my $db      = File::Spec->catdir($dir, "db");
  my $program = File::Spec->catfile($dir, "program.pl");
  open my $fh, ">", $program or die "open $program: $!";
  print $fh $Fixture;
  close $fh or die "close $program: $!";
  my $mod = File::Spec->catfile($dir, "TestMod.pm");
  open $fh, ">", $mod or die "open $mod: $!";
  print $fh "package TestMod;\n1;\n";
  close $fh or die "close $mod: $!";
  my $out = qq("$^X" "-I$Blib_lib" "-I$Blib_arch" "-I$dir" )
    . qq("-MDevel::Cover=-silent,1,-db,$db" "$program" 2>&1);
  $out = `$out`;
  note $out;
  is $?, 0, "the fixture runs cleanly";
  my %count = $out =~ /(\w+)=(\d+)/g;
  \%count
}

sub main () {
  my $count    = run_fixture;
  my $baseline = $count->{baseline};
  like $baseline, qr/^\d+$/, "the baseline reference count is read";
  for my $crit (qw( branch condition module )) {
    is $count->{$crit}, $baseline, "the $crit array has no extra reference";
  }
  done_testing;
}

main;

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin    ();
use File::Spec ();

use Test::More import => [qw( done_testing is_deeply like )];

my $Root = File::Spec->catdir($FindBin::Bin, "..", "..");

sub slurp ($file) {
  open my $fh, "<", $file or die "Can't open $file: $!";
  my $src = do { local $/; <$fh> };
  close $fh or die "Can't close $file: $!";
  $src
}

sub installed_scripts () {
  my $src = slurp(File::Spec->catfile($Root, "Makefile.PL"));
  my ($list) = $src =~ m|EXE_FILES\s*=>\s*\[map "bin/\$_", qw\( (.*?) \)\]|;
  [split " ", $list // ""]
}

sub bin_scripts () {
  my $bin = File::Spec->catdir($Root, "bin");
  opendir my $dh, $bin or die "Can't open $bin: $!";
  my @scripts = sort grep !/^\./, readdir $dh;
  closedir $dh or die "Can't close $bin: $!";
  @scripts
}

sub test_installed () {
  is_deeply installed_scripts, [qw( cover gcov2perl )],
    "only the end user commands are installed";
}

# Uninstalled scripts are run from a checkout, so they miss the shebang
# rewriting MakeMaker does on installation.
sub test_shebangs () {
  my %installed = map { $_ => 1 } installed_scripts->@*;
  for my $script (bin_scripts) {
    next if $installed{$script};
    my $src = slurp(File::Spec->catfile($Root, "bin", $script));
    like $src, qr|\A\#!/usr/bin/env perl\n|,
      "$script runs under the perl on PATH";
  }
}

sub main () {
  test_installed;
  test_shebangs;
}

main;
done_testing;

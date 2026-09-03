#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Cwd        qw( abs_path getcwd );
use File::Path qw( make_path );
use File::Spec ();
use File::Temp qw( tempdir );

use Devel::Cover::DB;

use Test::More import => [qw( diag done_testing is ok plan )];

if ($^O eq "MSWin32") {
  plan skip_all => "fork uses threads on Windows";
  exit;
}

my $Project   = getcwd;
my $Blib_lib  = File::Spec->catdir($Project, "blib", "lib");
my $Blib_arch = File::Spec->catdir($Project, "blib", "arch");

unless (-d $Blib_lib && -d $Blib_arch) {
  plan skip_all => "build artefacts missing - run after `make`";
  exit;
}

my $Wrapper = <<'PERL';
package Wrapper;
sub go { exec @_ }
1;
PERL

sub write_file ($path, $content) {
  open my $fh, ">", $path or die "open $path: $!";
  print $fh $content;
  close $fh or die "close $path: $!";
}

# Runs $code in a child perl with Wrapper.pm ignored and returns the database
# path, the program path and the child's exit status.
sub run_child ($code, @options) {
  my $dir = tempdir(CLEANUP => 1);
  my $lib = File::Spec->catdir($dir, "lib");
  make_path $lib;
  write_file(File::Spec->catfile($lib, "Wrapper.pm"), $Wrapper);
  my $program = File::Spec->catfile($dir, "program.pl");
  write_file($program, $code);
  my $db      = File::Spec->catdir($dir, "db");
  my $options = join ",", "-silent,1", "-db,$db", "-ignore,Wrapper", @options;
  my $cmd     = qq("$^X" "-I$Blib_lib" "-I$Blib_arch" "-I$lib" )
    . qq("-MDevel::Cover=$options" "$program" 2>&1);
  my $out = `$cmd`;
  diag $out if length $out;
  ($db, $program, $?)
}

sub run_count ($db) {
  my $runs = File::Spec->catdir($db, "runs");
  return 0 unless -d $runs;
  opendir my $dh, $runs or die "opendir $runs: $!";
  my @runs = grep !/^\./, readdir $dh;
  closedir $dh;
  scalar @runs
}

sub statement_covered ($db, $program, $line) {
  my $cover = Devel::Cover::DB->new(db => $db)->merge_runs->cover;
  my $file  = $cover->file(abs_path $program) or return 0;
  my $loc   = $file->statement->location($line);
  $loc && $loc->[0]->covered
}

my $Exec_via_wrapper = <<'PERL';
use Wrapper;
my $x = 1;
Wrapper::go($^X, "-e", "exit 0");
PERL

sub test_exec_from_ignored_file (@options) {
  my $label = @options ? "@options" : "replaced ops";
  my ($db, $program, $status) = run_child($Exec_via_wrapper, @options);
  is $status,        0, "$label: the program exits cleanly";
  is run_count($db), 1, "$label: the exec-time report writes one run";
  ok statement_covered($db, $program, 2),
    "$label: the statement before the exec is covered";
}

sub test_forked_child_exec_still_vetoed () {
  my ($db, $program, $status) = run_child(<<'PERL');
use Wrapper;
my $pid = fork;
die "fork: $!" unless defined $pid;
if ($pid) { waitpid $pid, 0 } else { Wrapper::go($^X, "-e", "exit 0") }
PERL
  is $status,        0, "the forking program exits cleanly";
  is run_count($db), 1, "only the parent's END-time run is written";
}

sub main () {
  test_exec_from_ignored_file;
  test_forked_child_exec_still_vetoed;
  test_exec_from_ignored_file("-replace_ops,0");
  done_testing;
}

main;

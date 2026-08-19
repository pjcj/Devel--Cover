#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Fcntl      qw( LOCK_EX );
use File::Path qw( make_path );
use File::Spec ();
use File::Temp qw( tempdir );
use POSIX      qw( WNOHANG _exit );
use Test::More import => [qw( done_testing is is_deeply plan )];

BEGIN {
  plan skip_all => "flock is emulated on Windows" if $^O eq "MSWin32";
}

use Devel::Cover::DB::Structure ();

my $Tmpdir = tempdir(CLEANUP => 1);

sub write_source ($name, $content) {
  my $path = File::Spec->catfile($Tmpdir, $name);
  open my $fh, ">", $path or die "Can't write $path: $!";
  print $fh $content;
  close $fh or die "Can't close $path: $!";
  $path
}

sub structure_entries ($base) {
  opendir my $dh, "$base/structure" or die "Can't opendir $base/structure: $!";
  my @entries = sort grep !/^\.\.?$/, readdir $dh;
  closedir $dh;
  @entries
}

sub built_structure ($label) {
  my $file = write_source("$label.pm", "package Lock;\n1\n");
  my $base = File::Spec->catdir($Tmpdir, $label);
  make_path("$base/structure");
  my $st = Devel::Cover::DB::Structure->new(base => $base);
  $st->add_criteria("statement");
  $st->set_file($file);
  $st->{f}{$file}{statement} = [[$file, 1]];
  ($base, $st, $file)
}

sub test_write_lock_names () {
  my ($base, $st, $file) = built_structure("names");
  $st->write($base);
  my $digest = $st->{f}{$file}{digest};
  is_deeply [structure_entries($base)], [sort $digest, "$digest.lock"],
    "write leaves only the structure file and its lock";

  my @locks = grep /\.lock$/, structure_entries($base);
  is_deeply [sort map "$base/structure/$_", @locks],
    [sort glob "$base/structure/*.lock"],
    "every lock file is visible to the cleanup glob";
}

sub test_second_write () {
  my ($base, $st) = built_structure("rewrite");
  $st->write($base);
  my @before = structure_entries($base);
  $st->write($base);
  is_deeply [structure_entries($base)], \@before,
    "a second write adds no files";
}

sub test_read_back () {
  my ($base, $st, $file) = built_structure("read");
  $st->write($base);
  my $st2 = Devel::Cover::DB::Structure->new(base => $base);
  $st2->read_all;
  is_deeply $st2->{f}{$file}{statement}, [[$file, 1]],
    "the structure file reads back";
}

sub test_writer_waits () {
  my ($base, $st, $file) = built_structure("waits");
  $st->write($base);
  my $digest = $st->{f}{$file}{digest};
  my $lock   = "$base/structure/$digest.lock";
  open my $lfh, "+>>", $lock or die "Can't open $lock: $!";
  flock $lfh, LOCK_EX or die "Can't lock $lock: $!";

  my $pid = fork // die "Can't fork: $!";
  unless ($pid) {
    # drop the inherited lock handle so only the parent holds the lock
    close $lfh or _exit 1;
    my (undef, $child_st) = built_structure("waits");
    eval { $child_st->write($base) };
    _exit 0;
  }
  sleep 1;
  is waitpid($pid, WNOHANG), 0, "a writer waits for the lock holder";
  close $lfh or die "Can't close $lock: $!";
  is waitpid($pid, 0), $pid, "the writer finishes once the lock is free";
}

sub main () {
  test_write_lock_names;
  test_second_write;
  test_read_back;
  test_writer_waits;
}

main;
done_testing;

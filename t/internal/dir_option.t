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

use Test::More import => [qw( done_testing is ok plan skip )];

BEGIN {
  plan skip_all => "JSON::MaybeXS required for this test"
    unless eval "require JSON::MaybeXS; 1";
}

my $Root = getcwd;
my $Lib  = File::Spec->rel2abs("blib/lib");
my $Arch = File::Spec->rel2abs("blib/arch");

sub write_file ($path, $contents) {
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $contents;
  close $fh or die "Cannot close $path: $!";
}

sub make_dist () {
  my $dir = File::Spec->rel2abs(tempdir(CLEANUP => 1));
  make_path(map File::Spec->catdir($dir, $_), qw( inc blib ));
  write_file(File::Spec->catfile($dir, "inc", "Inc1.pm"), "package Inc1; 1;\n");
  write_file(
    File::Spec->catfile($dir, "run.pl"),
    qq(use lib "inc"; use Inc1;\nmy \$x = 0;\n\$x++ for 1 .. 3;\n),
  );
  $dir
}

sub read_run ($db) {
  my ($file) = grep !/\.lock$/,
    glob File::Spec->catfile($db, "runs", "*", "cover.*");
  open my $fh, "<", $file or die "Cannot read $file: $!";
  my $json = do { local $/; <$fh> };
  close $fh or die "Cannot close $file: $!";
  my ($run) = values JSON::MaybeXS::decode_json($json)->{runs}->%*;
  $run
}

sub run_with_dir ($dir, $dirarg, $program = "run.pl") {
  my $db = File::Spec->catdir($dir, "cover_db");
  local $ENV{DEVEL_COVER_SELF};
  local $ENV{DEVEL_COVER_OPTIONS};
  local $ENV{DEVEL_COVER_DB_FORMAT} = "JSON";
  delete @ENV{qw( DEVEL_COVER_SELF DEVEL_COVER_OPTIONS )};
  chdir $dir or die "Cannot chdir $dir: $!";
  my $status = system $^X, "-I$Lib", "-I$Arch",
    "-MDevel::Cover=-db,$db,-dir,$dirarg,-silent,1,-merge,0", $program;
  chdir $Root  or die "Cannot chdir $Root: $!";
  $status == 0 or die "Failed to run under Devel::Cover: $?";
  read_run($db)
}

sub check_run ($run, $dir, $name) {
  my @files = keys $run->{count}->%*;
  is $run->{dir}, abs_path($dir), "$name stores the resolved directory";
  ok exists $run->{count}{"run.pl"}, "$name stores run.pl by relative name";
  is grep(File::Spec->file_name_is_absolute($_), @files), 0,
    "$name stores no absolute file names";
  is grep(/Inc1/, @files), 0, "$name applies the default inc/ ignore";
}

sub test_relative_dir () {
  my $dir = make_dist;
  check_run(run_with_dir($dir, "."), $dir, "a relative -dir");
}

sub test_symlinked_dir () {
  SKIP: {
    skip "abs_path keeps symlinks on Windows", 4 if $^O eq "MSWin32";
    my $dir  = make_dist;
    my $link = File::Spec->catdir(tempdir(CLEANUP => 1), "link");
    skip "symlink not available", 4 unless eval { symlink $dir, $link };
    check_run(run_with_dir($dir, $link), $dir, "a symlinked -dir");
  }
}

sub test_symlinked_file () {
  SKIP: {
    my $dir = make_dist;
    make_path(map File::Spec->catdir($dir, $_), qw( script bin ));
    write_file(File::Spec->catfile($dir, "script", "tool.pl"), "my \$y = 1;\n");
    my $tool   = File::Spec->catfile($dir, "bin", "tool");
    my $link   = File::Spec->catdir(tempdir(CLEANUP => 1), "link");
    my $linked = eval { symlink "../script/tool.pl", $tool }
      && eval { symlink $dir, $link };
    skip "symlink not available", 2 unless $linked;
    my $run = run_with_dir($dir, $link, "$link/bin/tool");
    ok exists $run->{count}{"bin/tool"}, "a symlinked file stores bin/tool";
    is grep(File::Spec->file_name_is_absolute($_), keys $run->{count}->%*), 0,
      "a symlinked file stores no absolute file names";
  }
}

sub main () {
  test_relative_dir;
  test_symlinked_dir;
  test_symlinked_file;
  done_testing;
}

main;

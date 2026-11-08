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
use File::Glob qw( bsd_glob );
use File::Spec ();
use File::Temp qw( tempdir );

use Test::More import => [qw( done_testing like ok plan unlike )];

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

sub read_file ($path) {
  open my $fh, "<", $path or die "Cannot read $path: $!";
  my $contents = do { local $/; <$fh> };
  close $fh or die "Cannot close $path: $!";
  $contents
}

sub run_perl ($dir, $out, @args) {
  my @cmd = ($^X, "-I$Lib", "-I$Arch", @args);
  local $ENV{DEVEL_COVER_SELF};
  local $ENV{DEVEL_COVER_OPTIONS};
  local $ENV{DEVEL_COVER_DB_FORMAT} = "JSON";
  delete @ENV{qw( DEVEL_COVER_SELF DEVEL_COVER_OPTIONS )};
  chdir $dir or die "Cannot chdir $dir: $!";
  my $status = system join " ", map(qq("$_"), @cmd), qq(> "$out" 2>&1);
  chdir $Root or die "Cannot chdir $Root: $!";
  $status == 0 or die "Failed to run @cmd: $?\n", read_file($out);
  read_file($out)
}

sub run_covered ($dir, $program, @args) {
  my $out = File::Spec->catfile($dir, "$program.out");
  run_perl($dir, $out, "-MDevel::Cover=-db,DB", $program, @args)
}

sub run_files ($db) {
  grep !/\.lock$/, bsd_glob(File::Spec->catfile($db, "runs", "*", "cover.*"))
}

sub read_run ($file) {
  my $runs = JSON::MaybeXS::decode_json(read_file($file))->{runs};
  my ($run) = values %$runs;
  $run
}

sub test_renamed_file () {
  my $dir = File::Spec->rel2abs(tempdir(CLEANUP => 1));
  my $db  = File::Spec->catdir($dir, "DB");
  my $old = File::Spec->catfile($dir, "tool");
  my $new = File::Spec->catfile($dir, "newtool");
  write_file(
    $old,
    qq[my \$x = shift; if (\$x) { print "yes\\n" } else { print "no\\n" }\n],
  );

  run_covered($dir, "tool", 1);
  my $first = { map { $_ => 1 } run_files($db) };
  rename $old, $new or die "Cannot rename $old to $new: $!";
  my $out = run_covered($dir, "newtool", 0);

  my ($file) = grep !$first->{$_}, run_files($db);
  ok $file, "the second run writes its own run file";
  my $run = read_run($file);
  ok $run->{count}{newtool}{branch},
    "the second run counts branches of newtool";
  ok !exists $run->{digests}{tool}, "the second run has no digest for tool";
  ok defined $run->{digests}{newtool},
    "the second run has a digest for newtool";
  unlike $out, qr/Can't find file/, "the second run finds its file";

  my $log    = File::Spec->catfile($dir, "cover.out");
  my $report = run_perl($Root, $log, qw( bin/cover -report text ), $db);
  like $report, qr/^Total\s+\S+\s+100\.0\s/m,
    "the merged runs cover both branches";
}

sub test_changed_directory () {
  my $dir  = File::Spec->rel2abs(tempdir(CLEANUP => 1));
  my $out  = abs_path(tempdir(CLEANUP => 1));
  my $db   = File::Spec->catdir($dir, "DB");
  my $code = "package Same; sub f { \$_[0] ? 1 : 2 } 1;\n";
  write_file(File::Spec->catfile($dir, "Same.pm"), $code);
  write_file(File::Spec->catfile($out, "Same.pm"), $code);
  write_file(
    File::Spec->catfile($dir, "first.pl"),
    qq[use lib "."; use Same; Same::f(1);\n],
  );
  mkdir File::Spec->catdir($dir, "sub") or die "Cannot mkdir sub: $!";
  write_file(
    File::Spec->catfile($dir, "second.pl"),
    qq[chdir "sub" or die; require "$out/Same.pm"; Same::f(0);\n],
  );

  run_covered($dir, "first.pl");
  my $first = { map { $_ => 1 } run_files($db) };
  run_covered($dir, "second.pl");

  my ($file) = grep !$first->{$_}, run_files($db);
  my $run    = read_run($file);
  ok $run->{count}{"Same.pm"},
    "a run in another directory counts the copy as Same.pm";
  ok !exists $run->{count}{"$out/Same.pm"},
    "a run in another directory has no count for the copy";
}

sub main () {
  test_renamed_file;
  test_changed_directory;
}

main;
done_testing;

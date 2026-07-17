#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# add_uncoverable is the engine behind `cover -add_uncoverable_point`. Each
# "$file $crit $line $count $type $class $note" spec is appended to the
# .uncoverable file with its source line keyed by the line's MD5 digest.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

# Digest::MD5 is deliberately not loaded here - DB.pm must load it itself
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is ok )];

use Devel::Cover::DB ();

my $Tmpdir = tempdir(CLEANUP => 1);

sub write_source ($name, $content) {
  my $path = File::Spec->catfile($Tmpdir, $name);
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
  $path
}

# Two specs in one call confirm each $adds entry is parsed individually rather
# than via a single shared topic variable.
sub test_records_specs () {
  my $src = write_source("source.pl", "line one\nline two\nline three\n");
  my $unc = File::Spec->catfile($Tmpdir, ".uncoverable");

  my $db  = Devel::Cover::DB->new(uncoverable_file => [$unc]);
  my $err = do {
    local $@;
    eval {
      $db->add_uncoverable([
        "$src branch 2 0 0 default note-two",
        "$src statement 3 0 0 default note-three",
      ]);
      1
    } ? "" : $@
  };
  is $err, "", "add_uncoverable: works without caller loading Digest::MD5";

  ok -e $unc, "add_uncoverable: writes the .uncoverable file";

  open my $fh, "<", $unc or die "Cannot read $unc: $!";
  my @lines = <$fh>;
  close $fh or die "Cannot close $unc: $!";

  require Digest::MD5;
  my $md5_two   = Digest::MD5->new->add("line two\n")->hexdigest;
  my $md5_three = Digest::MD5->new->add("line three\n")->hexdigest;

  is $lines[0], "$src branch $md5_two 0 0 default note-two\n",
    "add_uncoverable: first spec keyed by source-line digest";
  is $lines[1], "$src statement $md5_three 0 0 default note-three\n",
    "add_uncoverable: second spec parsed independently";
}

# uncoverable() is the other Digest::MD5 call site in DB.pm. Round-trip a spec
# through add_uncoverable and confirm it comes back keyed by the file digest
# with the line digest translated back to a line number.
sub test_uncoverable_round_trip () {
  my $src = write_source("round_trip.pl", "line one\nline two\n");
  my $unc = File::Spec->catfile($Tmpdir, ".uncoverable_round_trip");

  my $db = Devel::Cover::DB->new(uncoverable_file => [$unc]);
  $db->add_uncoverable(["$src branch 2 0 0 default note-two"]);

  my $u;
  local $Devel::Cover::Silent = 1;  # keep dcinfo quiet
  my $err = do {
    local $@;
    eval { $u = $db->uncoverable; 1 } ? "" : $@
  };
  is $err, "", "uncoverable: works without caller loading Digest::MD5";

  # Read in text mode, matching how uncoverable() digests the file
  my $file_digest = do {
    open my $fh, "<", $src or die "Cannot open $src: $!";
    require Digest::MD5;
    my $md5 = Digest::MD5->new;
    while (my $l = <$fh>) { $md5->add($l) }
    $md5->hexdigest
  };
  ok exists $u->{$file_digest}{branch}{2},
    "uncoverable: entry keyed by file digest and line number";
}

sub main () {
  test_records_specs;
  test_uncoverable_round_trip;
}

main;
done_testing;

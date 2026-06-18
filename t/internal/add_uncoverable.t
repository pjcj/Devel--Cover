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

use Digest::MD5 ();
use File::Spec  ();
use File::Temp  qw( tempdir );
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

  my $db = Devel::Cover::DB->new(uncoverable_file => [$unc]);
  $db->add_uncoverable([
    "$src branch 2 0 0 default note-two",
    "$src statement 3 0 0 default note-three",
  ]);

  ok -e $unc, "add_uncoverable: writes the .uncoverable file";

  open my $fh, "<", $unc or die "Cannot read $unc: $!";
  my @lines = <$fh>;
  close $fh or die "Cannot close $unc: $!";

  my $md5_two   = Digest::MD5->new->add("line two\n")->hexdigest;
  my $md5_three = Digest::MD5->new->add("line three\n")->hexdigest;

  is $lines[0], "$src branch $md5_two 0 0 default note-two\n",
    "add_uncoverable: first spec keyed by source-line digest";
  is $lines[1], "$src statement $md5_three 0 0 default note-three\n",
    "add_uncoverable: second spec parsed independently";
}

sub main () {
  test_records_specs;
}

main;
done_testing;

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

use File::Temp ();
use Test::More import => [qw( done_testing is plan )];

use Devel::Cover::DB::IO::Base     ();
use Devel::Cover::DB::IO::Storable ();

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

my $Dir = File::Temp->newdir;

write_file("$Dir/probe", "x");
plan skip_all => "hardlinks not supported"
  unless eval { link "$Dir/probe", "$Dir/probe2" };

# write_fh contract: the data goes to a tmp file and the target stays
# intact until the rename
{
  my $file = "$Dir/data";
  write_file($file, "old");
  link $file, "$Dir/seeded" or die "Can't link $file: $!";

  my $io = Devel::Cover::DB::IO::Base->new;
  $io->write_fh(
    $file,
    sub ($fh) {
      my @writing = glob "$file.tmp*";
      is @writing,     1,     "writer writes to a tmp file";
      is slurp($file), "old", "target is untouched while writing";
      print $fh "new";
    },
  );

  is slurp($file),         "new", "target has the new content";
  is slurp("$Dir/seeded"), "old", "hardlinked copy keeps the old content";
  my $nlink = (stat $file)[3];
  is $nlink, 1, "target no longer shares its inode";
  my @tmp = glob "$Dir/data.tmp*";
  is @tmp, 0, "no tmp files remain";
}

# IO::Storable's public interface
{
  my $file = "$Dir/db";
  my $io   = Devel::Cover::DB::IO::Storable->new;
  $io->write({ key => "first" }, $file);
  link $file, "$Dir/db.seeded" or die "Can't link $file: $!";
  $io->write({ key => "second" }, $file);

  is $io->read($file)->{key}, "second", "storable file has the new data";
  is $io->read("$Dir/db.seeded")->{key}, "first",
    "seeded storable copy keeps the old data";
}

SKIP: {
  Test::More::skip "JSON::MaybeXS required for this test", 2
    unless eval { require Devel::Cover::DB::IO::JSON; 1 };

  my $file = "$Dir/cover.json";
  my $io   = Devel::Cover::DB::IO::JSON->new;
  $io->write({ key => "first" }, $file);
  link $file, "$Dir/cover.json.seeded" or die "Can't link $file: $!";
  $io->write({ key => "second" }, $file);

  is $io->read($file)->{key}, "second", "json file has the new data";
  is $io->read("$Dir/cover.json.seeded")->{key}, "first",
    "seeded json copy keeps the old data";
}

done_testing;

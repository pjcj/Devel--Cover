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
use Test::More import => [qw( done_testing is like plan )];

use Devel::Cover::Web qw( write_file );

sub spew ($path, $content) {
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

spew("$Dir/probe", "x");
plan skip_all => "hardlinks not supported"
  unless eval { link "$Dir/probe", "$Dir/probe2" };

my $File = "$Dir/collection.css";
spew($File, "old");
link $File, "$Dir/seeded" or die "Can't link $File: $!";

write_file("$Dir", "collection.css");

like slurp($File), qr/Devel::Cover/, "target has the asset content";
is slurp("$Dir/seeded"), "old", "hardlinked copy keeps the old content";
my $Nlink = (stat $File)[3];
is $Nlink, 1, "target no longer shares its inode";
my @Tmp = glob "$Dir/collection.css.tmp*";
is @Tmp, 0, "no tmp files remain";

done_testing;

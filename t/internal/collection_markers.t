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

use File::Path qw( make_path );
use File::Temp ();
use Test::More import => [qw( done_testing is isnt plan )];

BEGIN {
  plan skip_all => "Devel::Cover::Collection requires Perl 5.42" if $] < 5.042;
  plan skip_all => "Devel::Cover::Collection is not portable to Windows"
    if $^O eq "MSWin32";
  for my $module (qw( Template Parallel::Iterator JSON::MaybeXS )) {
    plan skip_all => "$module required for this test"
      unless eval "require $module; 1";
  }
}

use Devel::Cover::Collection ();

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

my $Dist = "Foo-Bar-1.00";
my $Dir  = File::Temp->newdir;

for my $set (qw( __failed__ __rebuilt__ )) {
  make_path("$Dir/$set");
  write_file("$Dir/$set/$Dist", "prod");
  link "$Dir/$set/$Dist", "$Dir/$set/$Dist.seeded"
    or plan skip_all => "hardlinks not supported";
}

my $Collection = Devel::Cover::Collection->new(results_dir => "$Dir");
$Collection->set_failed($Dist);
$Collection->set_rebuilt($Dist);

for my $set (qw( __failed__ __rebuilt__ )) {
  my $marker = "$Dir/$set/$Dist";
  isnt slurp($marker), "prod", "$set marker is rewritten";
  is slurp("$marker.seeded"), "prod",
    "seeded $set marker keeps the old content";
  my $nlink = (stat $marker)[3];
  is $nlink, 1, "$set marker no longer shares its inode";
}

my @Tmp = map glob, "$Dir/__failed__/*.tmp.*", "$Dir/__rebuilt__/*.tmp.*";
is @Tmp, 0, "no tmp files remain";

done_testing;

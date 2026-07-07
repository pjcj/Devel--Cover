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

use Cwd        qw( getcwd );
use File::Path qw( make_path );
use File::Temp ();
use JSON::PP   ();
use Test::More import => [qw( done_testing like plan unlike )];

BEGIN {
  plan skip_all => "Devel::Cover::Collection requires Perl 5.42" if $] < 5.042;
  for my $module (qw( Template Parallel::Iterator JSON::MaybeXS )) {
    plan skip_all => "$module required for this test"
      unless eval "require $module; 1";
  }
}

require Devel::Cover::Collection;

my $Dist = "Foo-Bar-1.00";
my $Log  = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--1234567890.123456.out.gz";

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

sub setup_results_dir {
  my $dir = File::Temp->newdir;
  make_path("$dir/$Dist");

  my $criterion = { percentage => 85.5, covered => 10, total => 12 };
  my $cover     = {
    runs    => [{ name => "Foo-Bar", version => "1.00", dir => "/tmp/x" }],
    summary => { Total => { total => $criterion, statement => $criterion } },
  };
  write_file("$dir/$Dist/cover.json", JSON::PP->new->encode($cover));
  write_file("$dir/$Log",             "log\n");

  $dir
}

my $Cwd = getcwd;
my $Dir = setup_results_dir;

my $Collection = Devel::Cover::Collection->new(results_dir => "$Dir");
$Collection->generate_html;
chdir $Cwd or die "Can't chdir $Cwd: $!";

my %Page = (
  index => slurp("$Dir/index.html"),
  dist  => slurp("$Dir/dist/F.html"),
  about => slurp("$Dir/about.html"),
);

for my $name (sort keys %Page) {
  unlike $Page{$name}, qr{/latest/},        "$name page has no /latest/ links";
  unlike $Page{$name}, qr{(?:href|src)="/}, "$name page has no absolute links";
}

for my $name (qw( index about )) {
  like $Page{$name}, qr{href="collection\.css"},
    "$name page links stylesheet relatively";
  like $Page{$name}, qr{src="collection\.js"},
    "$name page links script relatively";
  like $Page{$name}, qr{href="about\.html"},
    "$name page links about page relatively";
}

like $Page{index}, qr{href="dist/F\.html"}, "index links dist page";

like $Page{dist}, qr{href="\.\./collection\.css"}, "dist page links stylesheet";
like $Page{dist}, qr{src="\.\./collection\.js"},   "dist page links script";
like $Page{dist}, qr{href="\.\./about\.html"},     "dist page links about page";
like $Page{dist}, qr{href="\.\./\Q$Dist\E/index\.html"},
  "dist page links module report";
like $Page{dist}, qr{href="\.\./\Q$Log\E"}, "dist page links build log";

done_testing;

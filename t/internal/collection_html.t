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

use Cwd        qw( getcwd );
use File::Path qw( make_path );
use File::Temp ();
use JSON::PP   ();
use Test::More import => [qw( done_testing is like plan unlike )];

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
use Devel::Cover::Inc        ();

my $Dist    = "Foo-Bar-1.00";
my $Log     = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--1234567890.123456.out.gz";
my $Log_new = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--1234567899.123456.out.gz";
my $Dist2   = "Baz-Qux-2.00";
my $Log2    = "P-PJ-PJCJ-Baz-Qux-2.00.tar.gz--1234567891.123456.out";
my $Dist3   = "Dangle-Ref-3.00";
my $Log3    = "P-PJ-PJCJ-Dangle-Ref-3.00.tar.gz--1234567892.123456.out";
my $Ref3    = "P-PJ-PJCJ-Dangle-Ref-3.00.tar.gz--9999999999.123456.out";
my $Dist4   = "Dep-Only-4.00";

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

sub write_dist ($dir, $dist, $name, $version, $log = undef) {
  make_path("$dir/$dist");

  my $criterion = { percentage => 85.5, covered => 10, total => 12 };
  my $cover     = {
    runs    => [{ name => $name, version => $version, dir => "/tmp/x" }],
    summary => { Total => { total => $criterion, statement => $criterion } },
  };
  write_file("$dir/$dist/cover.json", JSON::PP->new->encode($cover));
  write_file("$dir/$log",             "log\n") if defined $log;
}

sub seed_page ($dir, $file) {
  write_file("$dir/$file", "old");
  link "$dir/$file", "$dir/$file.seeded"
    or plan skip_all => "hardlinks not supported";
}

sub setup_results_dir {
  my $dir = File::Temp->newdir;
  write_dist($dir, $Dist,  "Foo-Bar", "1.00", $Log);
  write_dist($dir, $Dist2, "Baz-Qux", "2.00", $Log2);

  # $Dist was rebuilt: .log_ref names the newer log, both logs remain
  write_file("$dir/$Log_new",       "log\n");
  write_file("$dir/$Dist/.log_ref", "$Log_new\n");

  # $Dist3 has a dangling .log_ref but a name-matching log
  write_dist($dir, $Dist3, "Dangle-Ref", "3.00", $Log3);
  write_file("$dir/$Dist3/.log_ref", "$Ref3\n");

  # $Dist4 was built as a dependency: no own log, .log_ref names the
  # target's log
  write_dist($dir, $Dist4, "Dep-Only", "4.00");
  write_file("$dir/$Dist4/.log_ref", "$Log_new\n");

  make_path("$dir/dist");
  seed_page($dir, $_) for qw( index.html dist/F.html about.html );

  $dir
}

my $Cwd = getcwd;
my $Dir = setup_results_dir;

my $Collection = Devel::Cover::Collection->new(results_dir => "$Dir");
$Collection->generate_html;
chdir $Cwd or die "Can't chdir $Cwd: $!";

my %Page = (
  index  => slurp("$Dir/index.html"),
  dist   => slurp("$Dir/dist/F.html"),
  dist_b => slurp("$Dir/dist/B.html"),
  dist_d => slurp("$Dir/dist/D.html"),
  about  => slurp("$Dir/about.html"),
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
like $Page{dist}, qr{href="\.\./\Q$Log_new\E"},
  "dist page links the log named in .log_ref";
unlike $Page{dist}, qr{href="\.\./\Q$Log\E"},
  "dist page does not link the older log";
like $Page{dist_b}, qr{href="\.\./\Q$Log2\E"},
  "dist page links uncompressed build log";
like $Page{dist_d}, qr{href="\.\./\Q$Log3\E"},
  "dangling .log_ref falls back to the name-matched log";
unlike $Page{dist_d}, qr{href="\.\./\Q$Ref3\E"},
  "dangling .log_ref target is not linked";
like $Page{dist_d}, qr{href="\.\./\Q$Log_new\E"},
  "dependency dist links its target's log via .log_ref";

my $Version = $Devel::Cover::Inc::VERSION . $Devel::Cover::Inc::Dev;
for my $name (sort keys %Page) {
  like $Page{$name}, qr{Devel::Cover</a>\s+\Q$Version\E\s+by},
    "$name page footer shows the Devel::Cover version";
}

for my $f (qw( index.html dist/F.html about.html )) {
  is slurp("$Dir/$f.seeded"), "old", "$f is written atomically";
}
my @Tmp = map glob, "$Dir/*.tmp.*", "$Dir/dist/*.tmp.*";
is @Tmp, 0, "no tmp files remain";

done_testing;

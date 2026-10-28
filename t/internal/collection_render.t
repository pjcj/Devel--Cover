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

use Cwd            qw( getcwd );
use File::Basename qw( dirname );
use File::Path     qw( make_path );
use File::Temp     qw( tempdir );

use Test::More import => [qw( done_testing is isnt like ok plan )];

BEGIN {
  plan skip_all => "Devel::Cover::Collection requires Perl 5.42" if $] < 5.042;
  plan skip_all => "Devel::Cover::Collection is not portable to Windows"
    if $^O eq "MSWin32";
  for my $module (
    qw( Template Parallel::Iterator JSON::MaybeXS CPAN::DistnameInfo )
  ) {
    plan skip_all => "$module required for this test"
      unless eval "require $module; 1";
  }
}

use Devel::Cover::Collection ();

my $Tmp = tempdir CLEANUP => 1;
my $Bin = "$Tmp/bin";
make_path $Bin;

# A fake cover which records its arguments and writes the expected report file
open my $Fh, ">", "$Bin/cover" or die "Can't open $Bin/cover: $!";
print $Fh <<'EOS';
use strict;
use warnings;
use File::Path qw( make_path );
open my $afh, ">>", "cover_args" or die "Can't open cover_args: $!";
print $afh "@ARGV\n";
close $afh or die "Can't close cover_args: $!";
exit 1 if $ENV{FAKE_COVER_FAIL};
my ($i) = grep $ARGV[$_] eq "-outputdir", 0 .. $#ARGV;
defined $i or die "No -outputdir";
my $out = $ARGV[$i + 1];
make_path $out;
my $name
  = "@ARGV" =~ /-report html\b/         ? "index.html"
  : "@ARGV" =~ /-report json_summary\b/ ? "cover.json"
  :                                       die "Unknown report";
open my $ofh, ">", "$out/$name" or die "Can't open $out/$name: $!";
print $ofh "report\n";
close $ofh or die "Can't close $out/$name: $!";
exit 0;
EOS
close $Fh or die "Can't close $Bin/cover: $!";

sub slurp ($path) {
  open my $fh, "<", $path or die "Can't open $path: $!";
  my $content = do { local $/; <$fh> };
  close $fh or die "Can't close $path: $!";
  $content
}

sub spew ($path, $content) {
  open my $fh, ">", $path or die "Can't open $path: $!";
  print $fh $content;
  close $fh or die "Can't close $path: $!";
}

sub make_export ($dir, $build, %opt) {
  make_path "$dir/$_" for qw( cover_db/structure cover_db/runs/1 blib/lib );
  spew "$dir/cover_db/structure/abc",    "{}";
  spew "$dir/cover_db/runs/1/cover.15",  "{}";
  spew "$dir/cover_db/structure/x.lock", "";
  spew "$dir/blib/lib/Foo.pm",           "1;";
  spew "$dir/.select_dir",               "blib\n";
  spew "$dir/.build_dir",                "$build\n";
  return unless $opt{storable};
  make_path "$dir/cover_db/runs/2";
  spew "$dir/cover_db/runs/2/cover.15", "pst0";
}

my $N = 0;

sub dirs () {
  my $n = ++$N;
  ("$Tmp/in$n", "$Tmp/out$n", "$Tmp/cpan/build/My-Module-1.02-0-$n")
}

sub render ($in, $out, $build, $roots = ["$Tmp/cpan"]) {
  my $c   = Devel::Cover::Collection->new(bin_dir => $Bin, cpan_dir => $roots);
  my $cwd = getcwd;
  chdir $Tmp or die "Can't chdir $Tmp: $!";

  open my $saved_stdout, ">&", \*STDOUT     or die "Can't save STDOUT: $!";
  open STDOUT,           ">",  "$in.stdout" or die "Can't redirect STDOUT: $!";
  my $err = do {
    local $@;
    eval { $c->render_export($in, $out) };
    $@
  };
  open STDOUT, ">&", $saved_stdout or die "Can't restore STDOUT: $!";
  chdir $cwd or die "Can't chdir $cwd: $!";

  my $args = "$build/cover_args";
  {
    err    => $err,
    args   => -e $args ? slurp($args) : "",
    stdout => slurp("$in.stdout"),
  }
}

sub test_render_writes_report () {
  my ($in, $out, $build) = dirs;
  make_export $in, $build;
  my $r = render($in, $out, $build);
  is $r->{err}, "", "render succeeds";
  ok -e "$out/index.html", "render writes the html report";
  ok -e "$out/cover.json", "render writes the json summary";
  my @runs = split /\n/, $r->{args};
  is @runs, 2, "render runs cover twice";
  my ($html) = grep /-report html -outputfile index\.html\b/, @runs;
  my ($json) = grep /-report json_summary -nosummary\b/,      @runs;
  ok $html, "render writes an html report";
  ok $json, "render writes a json summary";

  for my $run ($html // "", $json // "") {
    like $run, qr/(?:^| )-nogcov\b/,                  "run turns gcov off";
    like $run, qr/(?:^| )-outputdir \Q$out\E(?: |$)/, "run writes to output";
    like $run, qr/(?:^| )cover_db(?: |$)/,            "run reads cover_db";
  }
  like $html // "", qr/(?:^| )-select_dir blib(?: |$)/, "html selects blib";
  ok -d $in,                  "render leaves the export in place";
  ok -d "$build/cover_db",    "render copies cover_db to the build dir";
  ok -e "$build/.select_dir", "render copies the markers to the build dir";
  ok -e "$build/cover_args",  "cover runs in the build dir";
  ok !-e "$in/cover_args",    "cover does not run in the export dir";
}

sub test_render_refuses_storable () {
  my ($in, $out, $build) = dirs;
  make_export $in, $build, storable => 1;
  my $r = render($in, $out, $build);
  like $r->{err}, qr/not JSON/,         "render refuses Storable";
  like $r->{err}, qr|runs/2/cover\.15|, "render names the Storable file";
  ok !-e "$in/cover_args",    "cover never runs on a Storable database";
  ok !-e "$build/cover_args", "cover never runs in the build dir";
}

sub test_render_refuses_bad_select_dir () {
  my ($in, $out, $build) = dirs;
  make_export $in, $build;
  spew "$in/.select_dir", "../etc\n";
  my $r = render($in, $out, $build);
  like $r->{err}, qr/select_dir/, "render refuses a bad select_dir";
  ok !-e "$in/cover_args",    "cover never runs with a bad select_dir";
  ok !-e "$build/cover_args", "cover never runs in the build dir";
}

sub test_render_refuses_bad_build_dir () {
  my @cases = (
    ["a relative path" => sub ($in, $out, $build) { ("build/My", $out) }],
    [
      "a .. component" => sub ($in, $out, $build) {
        ("$build/../My-Module-1.03-0", $out)
      },
    ], [
      "an existing path" => sub ($in, $out, $build) {
        make_path $build;
        ($build, $out)
      },
    ],
    ["the output dir" => sub ($in, $out, $build) { ($build, $build) }],
    [
      "a dir under output" =>
        sub ($in, $out, $build) { ($build, dirname $build) },
    ], [
      "a parent of output" =>
        sub ($in, $out, $build) { ($build, "$build/r") },
    ], [
      "a path outside the roots" => sub ($in, $out, $build) {
        ("$Tmp/elsewhere/build/My-Module-1.02-0", $out)
      },
    ], [
      "a path two levels down" =>
        sub ($in, $out, $build) { ("$build/My", $out) },
    ], [
      "the build directory" => sub ($in, $out, $build) {
        ("$in.cpan/build", $out, ["$in.cpan"])
      },
    ], [
      "the root" => sub ($in, $out, $build) {
        ("$in.cpan", $out, ["$in.cpan"])
      },
    ],
    ["/" => sub ($in, $out, $build) { ("/", $out) }],
    [
      "an empty component" => sub ($in, $out, $build) {
        ("$Tmp/cpan/build//My", $out)
      },
    ], [
      "a . component" => sub ($in, $out, $build) {
        ("$in.cpan/build/.", $out, ["$in.cpan"])
      },
    ], [
      "a .. name" => sub ($in, $out, $build) {
        ("$in.cpan/build/..", $out, ["$in.cpan"])
      },
    ],
    ["a trailing slash" => sub ($in, $out, $build) { ("$build/", $out) }],
    ["no roots" => sub ($in, $out, $build) { ($build, $out, []) }],
  );
  for my $case (@cases) {
    my ($name, $make) = @$case;
    my ($in, $out, $build) = dirs;
    make_export $in, $build;
    my ($bad, $to, @roots) = $make->($in, $out, $build);
    spew "$in/.build_dir", "$bad\n";
    my $r = render($in, $to, $build, @roots);
    like $r->{err}, qr/build_dir/, "render refuses $name as build_dir";
    ok -d $in, "render leaves the export with $name as build_dir";
    ok !-e "$_/cover_args", "cover never runs in $_ with $name as build_dir"
      for $in, $build, $to;
  }
}

sub test_render_option_reaches_render_export () {
  my ($in, $out, $build) = dirs;
  make_export $in, $build;
  spew "$in/.select_dir", "../etc\n";
  my $root = "$FindBin::Bin/../..";
  my $cmd  = join " ", $^X, "-I$root/lib", "$root/bin/cpancover",
    "--results_dir $Tmp/results --render", $in, $out;
  my $err = qx($cmd 2>&1);
  isnt $?, 0, "cpancover --render fails on a bad select_dir";
  like $err, qr|^Bad select_dir in \Q$in\E: \.\./etc$|m,
    "cpancover --render calls render_export";
}

sub test_render_requires_output () {
  my ($in, $out, $build) = dirs;
  make_export $in, $build;
  local $ENV{FAKE_COVER_FAIL} = 1;
  my $r = render($in, $out, $build);
  like $r->{err}, qr/Can't run/, "render fails when cover fails";
  ok !-e "$out/index.html", "no report is written when cover fails";
}

sub main () {
  test_render_writes_report;
  test_render_refuses_storable;
  test_render_refuses_bad_select_dir;
  test_render_refuses_bad_build_dir;
  test_render_option_reaches_render_export;
  test_render_requires_output;
}

main;
done_testing;

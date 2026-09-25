#!/usr/bin/perl
# HARNESS-DURATION-LONG

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# The dc recipes that read the CPAN release index. They live apart from
# xt/dc.t so that the daily index download holds up nothing else, and in one
# file because two CPAN::Releases::Latest runs at once may both write the
# cache file.

use 5.42.0;

use Test2::V0  qw( done_testing is isnt like ok skip_all subtest unlike );
use File::Temp qw( tempdir );

use CPAN::DistnameInfo       ();
use Devel::Cover::Collection ();

skip_all "dc recipes are not portable to Windows" if $^O eq "MSWin32";
skip_all "utils/dc not found" unless -x "utils/dc";
skip_all "pigz required" if system "pigz --version >/dev/null 2>&1";

my $Dc  = "utils/dc";
my $Log = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--1234567890.123456.out";

# runs a recipe and returns what it wrote to stderr
sub dc (@args) {
  my $cmd = join " ", $Dc, @args;
  my $err = tempdir(CLEANUP => 1) . "/err";
  system("$cmd >/dev/null 2>$err") == 0 or die "$cmd failed: " . slurp($err);
  slurp($err)
}

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

# an index in the CPAN::Releases::Latest cache format
sub write_index () {
  my $index = tempdir(CLEANUP => 1) . "/latest-releases.txt";
  write_file($index, <<~'INDEX');
    #FORMAT: 1
    Foo-Bar P/PJ/PJCJ/Foo-Bar-1.00.tar.gz 1234567890 1234
    Quux P/PJ/PJCJ/Quux-0.51.tar.gz 1234567891 1234
    INDEX
  $index
}

sub make_docker_stub ($bin) {
  write_file("$bin/docker", <<~'BASH');
    #!/bin/sh
    cmd="$1"
    shift
    echo "$cmd $*" >>"${STUB_CALLS:-/dev/null}"
    case "$cmd" in
      run) echo fake-container ;;
      logs) echo "fake build log" ;;
      cp)
        dest="$2"
        dist="$STUB_DISTDIR"
        mkdir -p "$dest/staging/$dist/runs" "$dest/staging/$dist/structure"
        echo db >"$dest/staging/$dist/cover.14"
        echo x >"$dest/staging/$dist/digests"
        echo x >"$dest/staging/$dist/x.lock"
        name="${dist%-*}"
        version="${dist##*-}"
        printf '%s%s%s%s\n' \
          '{"runs":[{"name":"'"$name"'","version":"'"$version"'",' \
          '"dir":"/tmp/x"}],"summary":{"Total":' \
          '{"total":{"percentage":85.5,"covered":10,"total":12}}}}' \
          >"$dest/staging/$dist/cover.json"
        echo html >"$dest/staging/$dist/index.html"
        ;;
    esac
    exit 0
    BASH
  chmod 0755, "$bin/docker" or die "Can't chmod docker stub: $!";
}

# Foo-Bar is current and already rebuilt, Baz-Qux is no longer on CPAN and
# Quux has a newer release, so the pass builds Quux-0.51 and nothing else
sub rebuild_batch_cleanup () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}         = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR} = "Quux-0.51";
  my $work = tempdir(CLEANUP => 1);

  my $dir = tempdir(CLEANUP => 1);
  mkdir "$dir/$_"
    or die "Can't mkdir $dir/$_: $!"
    for "Foo-Bar-1.00", "Baz-Qux-2.00", "Quux-0.50", "__rebuilt__";
  my $criterion = '{"percentage":85.5,"covered":10,"total":12}';
  for my $d (["Foo-Bar", "1.00"], ["Baz-Qux", "2.00"], ["Quux", "0.50"]) {
    my ($name, $version) = @$d;
    write_file("$dir/$name-$version/cover.json",
          qq({"runs":[{"name":"$name","version":"$version","dir":"/tmp/x"}],)
        . qq("summary":{"Total":{"total":$criterion,"statement":$criterion}}}));
    write_file("$dir/$name-$version/index.html", "html\n");
  }
  write_file("$dir/__rebuilt__/Foo-Bar-1.00", "1234567890\n");
  write_file("$dir/$Log",                     "log\n");
  write_file("$dir/index.html.gz",            "stale\n");

  delete local $ENV{CPANCOVER_COMPRESS};
  local $ENV{CPANCOVER_LATEST_INDEX} = write_index;
  my $err;
  {
    local $ENV{STUB_CALLS} = "$work/calls";
    $err = dc("-r", $dir, "cpancover-rebuild-batch");
  }

  unlike $err, qr/Can't read the CPAN release index/,
    "the fixed index is read in place of the cache";
  ok -e "$dir/__rebuilt__/Baz-Qux-2.00",
    "a distribution the index no longer lists is marked rebuilt";
  ok -e "$dir/__rebuilt__/Quux-0.50", "a superseded release is marked rebuilt";
  my @runs = grep /^run /, split /\n/, slurp("$work/calls");
  is scalar @runs, 1, "one docker build is launched";
  like $runs[0], qr{P/PJ/PJCJ/Quux-0\.51\.tar\.gz},
    "the build is of the release that superseded the candidate";
  ok -s "$dir/Quux-0.51/cover.json", "the newer release has a report";
  ok -s "$dir/index.html",           "rebuild batch regenerates the index";
  like slurp("$dir/index.html"), qr/1 no longer on CPAN/,
    "the overview counts the distribution the index no longer lists";
  ok !-e "$dir/index.html.gz", "stale top-level .gz removed";
  my @locks = map glob, "$dir/*.lock", "$dir/*/*.lock";
  is \@locks, [], "no lock sidecars remain";
}

sub rebuild_module_recipe () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}         = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR} = "Foo-Bar-1.00";
  my $module = "P/PJ/PJCJ/Foo-Bar-1.00.tar.gz";
  my $work   = tempdir(CLEANUP => 1);

  my $dir = tempdir(CLEANUP => 1);

  mkdir "$dir/$_"
    or die "Can't mkdir $dir/$_: $!"
    for "Foo-Bar-1.00", "__rebuilt__";
  write_file("$dir/Foo-Bar-1.00/cover.json",  "{}\n");
  write_file("$dir/Foo-Bar-1.00/index.html",  "old\n");
  write_file("$dir/__rebuilt__/Foo-Bar-1.00", "1234567890\n");
  write_file("$dir/$Log",                     "log\n");

  delete local $ENV{CPANCOVER_COMPRESS};
  local $ENV{CPANCOVER_LATEST_INDEX} = write_index;
  my $err;
  {
    local $ENV{STUB_CALLS} = "$work/calls";
    $err = dc("-r", $dir, "cpancover-rebuild-module", $module);
  }

  unlike $err, qr/Can't read the CPAN release index/,
    "the fixed index is read in place of the cache";
  like slurp("$work/calls"), qr/\brun\b/, "rebuild launches a docker build";
  is slurp("$dir/Foo-Bar-1.00/index.html"), "html\n", "distdir is replaced";
  isnt slurp("$dir/__rebuilt__/Foo-Bar-1.00"), "1234567890\n",
    "rebuilt marker is rewritten";
  ok -s "$dir/index.html", "HTML is regenerated";
  unlike slurp("$dir/index.html"), qr/no longer on CPAN/,
    "the distribution the index lists is counted";
  my @locks = map glob, "$dir/*.lock", "$dir/*/*.lock";
  is \@locks, [], "no lock sidecars remain";
}

# The real index, so that a change upstream in what the rebuild pass relies
# on still shows up. Skipped where the index cannot be fetched or cached.
sub live_index () {
  delete local $ENV{CPANCOVER_LATEST_INDEX};
  my @paths = eval { Devel::Cover::Collection->new->latest_paths };
  skip_all "Can't read the CPAN release index: $@" if $@;

  ok @paths > 20_000, "the index lists every distribution on CPAN";
  my $ext = qr/\.(?:zip|tgz|tar\.(?:gz|bz2|xz))/;
  my @odd = grep !m{^[A-Z]/[A-Z]{2}/[A-Z0-9-]+/[^/]+$ext$}, @paths;
  is \@odd, [], "every path has the author directory form";
  my %seen;
  my @repeated = grep $seen{$_}++, @paths;
  is \@repeated, [], "no path is listed twice";
  my %per_dist;
  $per_dist{$_}++
    for grep defined, map CPAN::DistnameInfo->new($_)->dist, @paths;
  my @many = sort grep $per_dist{$_} > 2, keys %per_dist;
  is \@many, [], "each distribution has at most a stable and a dev release";
}

sub main () {
  my @tests = qw(
    rebuild_batch_cleanup
    rebuild_module_recipe
    live_index
  );
  for my $test (@tests) {
    no strict qw( refs );
    subtest $test => \&$test;
  }
  done_testing;
}

main;

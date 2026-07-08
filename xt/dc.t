#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.42.0;

use Test2::V0  qw( done_testing is ok skip_all subtest );
use File::Temp qw( tempdir );

skip_all "dc recipes are not portable to Windows" if $^O eq "MSWin32";
skip_all "utils/dc not found" unless -x "utils/dc";
skip_all "pigz required" if system "pigz --version >/dev/null 2>&1";

my $Dc  = "utils/dc";
my $Log = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--1234567890.123456.out";

sub dc (@args) {
  my $cmd = join " ", $Dc, @args;
  system("$cmd >/dev/null 2>&1") == 0 or die "$cmd failed";
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

sub make_results_tree () {
  my $dir = tempdir(CLEANUP => 1);
  for my $d ("Foo-Bar-1.00", "Foo-Bar-1.00/runs", "dist") {
    mkdir "$dir/$d" or die "Can't mkdir $dir/$d: $!";
  }
  write_file("$dir/Foo-Bar-1.00/cover.json", "{}");
  write_file("$dir/Foo-Bar-1.00/index.html", "html\n");
  write_file("$dir/Foo-Bar-1.00/cover.14",   "db\n");
  write_file("$dir/$Log",                    "log\n");
  write_file("$dir/$_",                      "x\n")
    for qw( index.html about.html collection.css collection.js );
  write_file("$dir/cpancover.json", "{}");
  write_file("$dir/dist/F.html",    "html\n");
  write_file("$dir/index.html.gz",  "stale\n");
  write_file("$dir/dist/F.html.gz", "stale\n");
  $dir
}

sub compress_recipe () {
  my $dir = make_results_tree;
  dc("-r", $dir, "cpancover-compress");

  ok !-e "$dir/index.html.gz",                "stale top-level .gz removed";
  ok !-e "$dir/dist/F.html.gz",               "stale dist .gz removed";
  ok -e "$dir/$Log.gz",                       "top-level log compressed";
  ok !-e "$dir/$Log",                         "uncompressed top-level log gone";
  ok -e "$dir/Foo-Bar-1.00/index.html.gz",    "distdir html compressed";
  ok -e "$dir/Foo-Bar-1.00/index.html",       "sidecar created";
  ok !-s "$dir/Foo-Bar-1.00/index.html",      "sidecar is empty";
  ok -e "$dir/Foo-Bar-1.00/virtual_unzipped", "marker created";
  ok !-e "$dir/Foo-Bar-1.00/runs",            "runs stripped";
  ok !-e "$dir/Foo-Bar-1.00/cover.14",        "cover DB stripped";
  ok -s "$dir/index.html",  "top-level index left uncompressed";
  ok -s "$dir/dist/F.html", "dist page left uncompressed";
}

sub uncompress_recipe () {
  my $dir = make_results_tree;
  dc("-r", $dir, "cpancover-compress");

  dc("-r", $dir, "cpancover-uncompress-dir", "Foo-Bar-1.00");
  is slurp("$dir/Foo-Bar-1.00/index.html"), "html\n",
    "uncompress restores content";
  ok !-e "$dir/Foo-Bar-1.00/index.html.gz", "uncompress removes .gz";

  dc("-r", $dir, "cpancover-uncompress-dir", "Foo-Bar-1.00");
  is slurp("$dir/Foo-Bar-1.00/index.html"), "html\n",
    "uncompress is a no-op on an uncompressed dir";
}

sub make_docker_stub ($bin) {
  write_file("$bin/docker", <<~'BASH');
    #!/bin/sh
    cmd="$1"
    shift
    case "$cmd" in
      run) echo fake-container ;;
      logs) echo "fake build log" ;;
      wait) sleep "${STUB_WAIT_SLEEP:-0}" ;;
      cp)
        dest="$2"
        dist="$STUB_DISTDIR"
        mkdir -p "$dest/staging/$dist/runs" "$dest/staging/$dist/structure"
        echo db >"$dest/staging/$dist/cover.14"
        echo x >"$dest/staging/$dist/digests"
        echo x >"$dest/staging/$dist/x.lock"
        echo '{}' >"$dest/staging/$dist/cover.json"
        echo html >"$dest/staging/$dist/index.html"
        ;;
    esac
    exit 0
    BASH
  chmod 0755, "$bin/docker" or die "Can't chmod docker stub: $!";
}

sub docker_module_log_ref () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}         = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR} = "Foo-Bar-1.00";

  my $log = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--123.456";

  my $off = tempdir(CLEANUP => 1);
  {
    delete local $ENV{CPANCOVER_COMPRESS};
    dc("-r", $off, "cpancover-docker-module", "Foo::Bar", $log, $off);
  }
  is slurp("$off/Foo-Bar-1.00/.log_ref"), "$log.out\n",
    ".log_ref records .out when compression is off";
  ok !-e "$off/Foo-Bar-1.00/runs",      "runs stripped at ingest";
  ok !-e "$off/Foo-Bar-1.00/cover.14",  "cover DB stripped at ingest";
  ok !-e "$off/Foo-Bar-1.00/x.lock",    "lock stripped at ingest";
  ok -e "$off/Foo-Bar-1.00/index.html", "report survives ingest";
  ok -e "$off/Foo-Bar-1.00/cover.json", "cover.json survives ingest";

  my $on = tempdir(CLEANUP => 1);
  {
    local $ENV{CPANCOVER_COMPRESS} = 1;
    dc("-r", $on, "cpancover-docker-module", "Foo::Bar", $log, $on);
  }
  is slurp("$on/Foo-Bar-1.00/.log_ref"), "$log.out.gz\n",
    ".log_ref records .out.gz when compression is on";
}

sub docker_module_timeout_log_ref () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}              = "$bin:$ENV{PATH}";
  local $ENV{STUB_WAIT_SLEEP}   = 3;
  local $ENV{CPANCOVER_TIMEOUT} = 1;
  local $ENV{CPANCOVER_REBUILD} = 1;

  my $log     = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--123.456";
  my $staging = tempdir(CLEANUP => 1);
  my $distdir = "$staging/Foo-Bar-1.00";

  mkdir $distdir or die "Can't mkdir $distdir: $!";
  write_file("$distdir/.log_ref", "old\n");
  link "$distdir/.log_ref", "$distdir/.log_ref.seeded"
    or skip_all "hardlinks not supported";

  dc(
    "-r", $staging, "cpancover-docker-module", "Foo-Bar-1.00.tar.gz", $log,
    $staging,
  );

  is slurp("$distdir/.log_ref"), "$log.out\n", "timeout path rewrites .log_ref";
  is slurp("$distdir/.log_ref.seeded"), "old\n",
    "hardlinked copy keeps the old content";
  my @tmp = glob "$distdir/.log_ref.tmp.*";
  is @tmp, 0, "no tmp files remain";
}

sub main () {
  my @tests = qw(
    compress_recipe
    uncompress_recipe
    docker_module_log_ref
    docker_module_timeout_log_ref
  );
  for my $test (@tests) {
    no strict qw( refs );
    subtest $test => \&$test;
  }
  done_testing;
}

main;

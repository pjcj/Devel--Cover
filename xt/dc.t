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

my $Dc     = "utils/dc";
my $Log    = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--1234567890.123456.out";
my $Log_gz = "P-PJ-PJCJ-Baz-Qux-2.00.tar.gz--1234567891.123456.out";

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

sub rebuild_batch_cleanup () {
  my $dir = tempdir(CLEANUP => 1);
  mkdir "$dir/$_"
    or die "Can't mkdir $dir/$_: $!"
    for "Foo-Bar-1.00", "__rebuilt__";
  my $criterion = '{"percentage":85.5,"covered":10,"total":12}';
  write_file("$dir/Foo-Bar-1.00/cover.json",
        qq({"runs":[{"name":"Foo-Bar","version":"1.00","dir":"/tmp/x"}],)
      . qq("summary":{"Total":{"total":$criterion,"statement":$criterion}}}));
  write_file("$dir/Foo-Bar-1.00/index.html",  "html\n");
  write_file("$dir/__rebuilt__/Foo-Bar-1.00", "1234567890\n");
  write_file("$dir/$Log",                     "log\n");
  write_file("$dir/index.html.gz",            "stale\n");

  delete local $ENV{CPANCOVER_COMPRESS};
  dc("-r", $dir, "cpancover-rebuild-batch");

  ok -s "$dir/index.html",     "rebuild batch regenerates the index";
  ok !-e "$dir/index.html.gz", "stale top-level .gz removed";
  my @locks = (glob("$dir/*.lock"), glob("$dir/*/*.lock"));
  is \@locks, [], "no lock sidecars remain";
}

sub make_seed_source ($src) {
  mkdir "$src/$_"
    or die "Can't mkdir $src/$_: $!"
    for "Foo-Bar-1.00", "__failed__", "__rebuilt__", "dist";
  write_file("$src/Foo-Bar-1.00/cover.json",  "{}\n");
  write_file("$src/Foo-Bar-1.00/index.html",  "html\n");
  write_file("$src/Foo-Bar-1.00/.log_ref",    "$Log\n");
  write_file("$src/Foo-Bar-1.00/x.lock",      "lock\n");
  write_file("$src/__failed__/Bad-Dist-0.01", "1234567890\n");
  write_file("$src/__rebuilt__/Foo-Bar-1.00", "1234567890\n");
  write_file("$src/$Log",                     "log\n");
  write_file("$src/$Log_gz.gz",               "gzlog\n");
  write_file("$src/index.html",               "top\n");
  write_file("$src/index.html.gz",            "stale\n");
  write_file("$src/cpancover.json",           "{}\n");
  write_file("$src/.cpancover_status",        "modules=1\n");
  write_file("$src/dist/F.html",              "html\n");
  write_file("$src/dist/F.html.gz",           "stale\n");
}

sub inode ($path) { (stat $path)[1] }

sub seed_recipe () {
  my $base = tempdir(CLEANUP => 1);
  my $src  = "$base/src";
  my $dest = "$base/dest";
  mkdir $src or die "Can't mkdir $src: $!";
  make_seed_source($src);

  dc("cpancover-seed", $src, $dest);

  is slurp("$dest/Foo-Bar-1.00/index.html"), "html\n", "dist dir seeded";
  is inode("$dest/Foo-Bar-1.00/index.html"),
    inode("$src/Foo-Bar-1.00/index.html"), "dist files are hardlinked";
  is slurp("$dest/Foo-Bar-1.00/.log_ref"), "$Log\n", ".log_ref seeded";
  ok -e "$dest/__failed__/Bad-Dist-0.01", "failed markers seeded";
  is slurp("$dest/$Log"),       "log\n",            "top-level log seeded";
  is inode("$dest/$Log"),       inode("$src/$Log"), "logs are hardlinked";
  is slurp("$dest/$Log_gz.gz"), "gzlog\n",          "compressed log seeded";

  ok !-e "$dest/__rebuilt__",         "rebuilt markers excluded";
  ok !-e "$dest/dist",                "dist pages excluded";
  ok !-e "$dest/index.html",          "top-level index excluded";
  ok !-e "$dest/index.html.gz",       "stale top-level .gz excluded";
  ok !-e "$dest/cpancover.json",      "top-level json excluded";
  ok !-e "$dest/.cpancover_status",   "status file excluded";
  ok !-e "$dest/Foo-Bar-1.00/x.lock", "lock files excluded";

  my $rc = system "$Dc cpancover-seed $src $dest >/dev/null 2>&1";
  ok $rc != 0, "seeding over an existing destination fails";
}

sub main () {
  my @tests = qw(
    compress_recipe
    uncompress_recipe
    docker_module_log_ref
    docker_module_timeout_log_ref
    rebuild_batch_cleanup
    seed_recipe
  );
  for my $test (@tests) {
    no strict qw( refs );
    subtest $test => \&$test;
  }
  done_testing;
}

main;

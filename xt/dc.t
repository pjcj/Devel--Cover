#!/usr/bin/perl
# HARNESS-DURATION-LONG

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.42.0;

use Test2::V0  qw( diag done_testing is isnt like ok skip_all subtest unlike );
use Config     qw( %Config );
use Cwd        qw( realpath );
use File::Find qw( find );
use File::Temp qw( tempdir );

skip_all "dc recipes are not portable to Windows" if $^O eq "MSWin32";
skip_all "utils/dc not found" unless -x "utils/dc";
skip_all "pigz required" if system "pigz --version >/dev/null 2>&1";

my $Dc     = "utils/dc";
my $Log    = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--1234567890.123456.out";
my $Log_gz = "P-PJ-PJCJ-Baz-Qux-2.00.tar.gz--1234567891.123456.out";
my $Dist   = "P/PJ/PJCJ/Foo-Bar-1.00.tar.gz";

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
    echo "$cmd $*" >>"${STUB_CALLS:-/dev/null}"
    echo "env PERL_MM_USE_DEFAULT=${PERL_MM_USE_DEFAULT-unset}" \
      "AUTOMATED_TESTING=${AUTOMATED_TESTING-unset}" \
      "NONINTERACTIVE_TESTING=${NONINTERACTIVE_TESTING-unset}" \
      "EXTENDED_TESTING=${EXTENDED_TESTING-unset}" \
      >>"${STUB_CALLS:-/dev/null}"
    cover_json() {
      printf '%s%s%s\n' \
        '{"runs":[{"name":"Foo-Bar","version":"1.00","dir":"/tmp/x"}],' \
        '"summary":{"Total":' \
        '{"total":{"percentage":85.5,"covered":10,"total":12}}}}'
    }
    render_output() {
      [ -n "${STUB_NO_RENDER:-}" ] && exit 1
      mkdir -p "$1/output/assets"
      echo html >"$1/output/index.html"
      cover_json >"$1/output/cover.json"
      echo x >"$1/output/assets/app.js"
    }
    export_staging() {
      dest="$1"
      if [ -n "${STUB_STAGING_LINK:-}" ]; then
        ln -s "$STUB_LINK_TARGET" "$dest/staging"
        exit 0
      fi
      mkdir -p "$dest/staging"
      [ -n "${STUB_NO_DIST:-}" ] && exit 0
      dist="$STUB_DISTDIR"
      db="$dest/staging/$dist/cover_db"
      mkdir -p "$db/runs" "$db/structure" "$dest/staging/$dist/blib/lib"
      cover_json >"$db/cover.json"
      echo x >"$db/digests"
      echo x >"$dest/staging/$dist/blib/lib/Foo.pm"
      echo blib >"$dest/staging/$dist/.select_dir"
      echo evil >"$dest/staging/$dist/evil.html"
      if [ -n "${STUB_SYMLINKS:-}" ]; then
        ln -s / "$dest/staging/$dist/root"
        ln -s "$STUB_LINK_TARGET" "$dest/staging/Link-1.0"
      fi
      if [ -n "${STUB_HIDDEN_LINK:-}" ]; then
        mkdir "$dest/staging/$dist/hide"
        ln -s / "$dest/staging/$dist/hide/root"
        chmod 0300 "$dest/staging/$dist/hide"
      fi
      if [ -n "${STUB_EXTRA_DIRS:-}" ]; then
        mkdir -p "$dest/staging/__failed__" "$dest/staging/__rebuilt__" \
          "$dest/staging/Other-9.99" "$dest/staging/dist"
        echo x >"$dest/staging/__failed__/Victim-1.0"
        echo x >"$dest/staging/__rebuilt__/Victim-1.0"
        echo evil >"$dest/staging/Other-9.99/index.html"
        echo x >"$dest/staging/dist/x"
      fi
      if [ -n "${STUB_NEWLINE_DIR:-}" ]; then
        odd="$dest/staging/$dist
    "
        mkdir -p "$odd"
        echo evil >"$odd/index.html"
      fi
    }
    case "$cmd" in
      create) echo fake-render ;;
      run) echo fake-container ;;
      logs) echo "fake build log" ;;
      wait)
        case "$1" in
          *-render-*) sleep "${STUB_RENDER_WAIT_SLEEP:-0}" ;;
          *) sleep "${STUB_WAIT_SLEEP:-0}" ;;
        esac
        ;;
      cp)
        case "$2" in *:/home/cpancover/input*) exit 0 ;; esac
        case "$1" in
          *:/home/cpancover/output*) render_output "$2" ;;
          *:/home/cpancover/cover/staging*) export_staging "$2" ;;
        esac
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
    dc("-r", $off, "cpancover-docker-module", $Dist, $log, $off);
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
    dc("-r", $on, "cpancover-docker-module", $Dist, $log, $on);
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

sub docker_module_replaces_failed () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}         = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR} = "Foo-Bar-1.00";
  delete local $ENV{CPANCOVER_REBUILD};
  my $log = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--123.456";

  my $kept = tempdir(CLEANUP => 1);
  mkdir "$kept/Foo-Bar-1.00" or die "Can't mkdir $kept/Foo-Bar-1.00: $!";
  write_file("$kept/Foo-Bar-1.00/index.html", "old\n");
  dc("-r", $kept, "cpancover-docker-module", $Dist, $log, $kept);
  is slurp("$kept/Foo-Bar-1.00/index.html"), "old\n",
    "an existing report without a failed marker is kept";

  my $failed = tempdir(CLEANUP => 1);
  mkdir "$failed/$_"
    or die "Can't mkdir $failed/$_: $!"
    for "Foo-Bar-1.00", "__failed__";
  write_file("$failed/Foo-Bar-1.00/index.html", "old\n");
  write_file("$failed/__failed__/Foo-Bar-1.00", "1234567890\n");
  dc("-r", $failed, "cpancover-docker-module", $Dist, $log, $failed);
  is slurp("$failed/Foo-Bar-1.00/index.html"), "html\n",
    "an existing report with a failed marker is replaced";
}

sub docker_module_ingests_only_distdir () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}            = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR}    = "Foo-Bar-1.00";
  local $ENV{STUB_EXTRA_DIRS} = 1;
  delete local $ENV{CPANCOVER_COMPRESS};
  my $log = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--123.456";

  my $rebuild = tempdir(CLEANUP => 1);
  mkdir "$rebuild/$_"
    or die "Can't mkdir $rebuild/$_: $!"
    for "__failed__", "__rebuilt__", "Other-9.99";
  write_file("$rebuild/__failed__/Victim-1.0",  "1234567890\n");
  write_file("$rebuild/__rebuilt__/Victim-1.0", "1234567890\n");
  write_file("$rebuild/Other-9.99/index.html",  "old\n");
  {
    local $ENV{CPANCOVER_REBUILD} = 1;
    dc("-r", $rebuild, "cpancover-docker-module", $Dist, $log, $rebuild);
  }
  ok -e "$rebuild/Foo-Bar-1.00/index.html", "the expected distdir is ingested";
  is slurp("$rebuild/__failed__/Victim-1.0"), "1234567890\n",
    "the failed marker survives";
  is slurp("$rebuild/__rebuilt__/Victim-1.0"), "1234567890\n",
    "the rebuilt marker survives";
  is slurp("$rebuild/Other-9.99/index.html"), "old\n",
    "the report of another dist is kept in a rebuild";
  ok !-e "$rebuild/dist", "no dist directory is ingested";
  my $out = slurp("$rebuild/$log.out");
  like $out, qr/\b\Q$_\E\b/, "build log names $_"
    for qw( __failed__ __rebuilt__ Other-9.99 dist );

  my $failed = tempdir(CLEANUP => 1);
  delete local $ENV{CPANCOVER_REBUILD};
  mkdir "$failed/$_"
    or die "Can't mkdir $failed/$_: $!"
    for "__failed__", "Other-9.99";
  write_file("$failed/__failed__/Other-9.99", "1234567890\n");
  write_file("$failed/Other-9.99/index.html", "old\n");
  dc("-r", $failed, "cpancover-docker-module", $Dist, $log, $failed);
  is slurp("$failed/Other-9.99/index.html"), "old\n",
    "the failed report of another dist is kept";
  ok !-e "$failed/dist", "no dist directory is ingested";

  my $newline = tempdir(CLEANUP => 1);
  delete local $ENV{STUB_EXTRA_DIRS};
  local $ENV{STUB_NEWLINE_DIR} = 1;
  mkdir "$newline/Foo-Bar-1.00" or die "Can't mkdir $newline/Foo-Bar-1.00: $!";
  write_file("$newline/Foo-Bar-1.00/index.html", "old\n");
  {
    local $ENV{CPANCOVER_REBUILD} = 1;
    dc("-r", $newline, "cpancover-docker-module", $Dist, $log, $newline);
  }
  my $index = "$newline/Foo-Bar-1.00/index.html";
  is -e $index ? slurp($index) : undef, "html\n",
    "the expected distdir replaces the old report";
  opendir my $dh, $newline or die "Can't opendir $newline: $!";
  my @odd = grep /\n/, readdir $dh;
  closedir $dh;
  is \@odd, [], "no results entry has a newline in its name";
  like slurp("$newline/$log.out"),
    qr/ignored unexpected directory Foo-Bar-1\.00/,
    "build log names the dropped directory";
}

sub links_under ($dir) {
  my @links;
  find(
    { wanted => sub { push @links, $File::Find::name if -l }, no_chdir => 1 },
    $dir,
  );
  \@links
}

sub docker_module_drops_symlinks () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  my $victim = tempdir(CLEANUP => 1);
  write_file("$victim/secret.txt", "secret\n");
  local $ENV{PATH}             = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR}     = "Foo-Bar-1.00";
  local $ENV{STUB_SYMLINKS}    = 1;
  local $ENV{STUB_LINK_TARGET} = $victim;
  delete local $ENV{CPANCOVER_COMPRESS};
  my $log = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--123.456";

  my $results = tempdir(CLEANUP => 1);
  dc("-r", $results, "cpancover-docker-module", $Dist, $log, $results);

  is links_under($results), [], "no link survives ingest";
  ok !-e "$results/Link-1.0",          "a top-level link is not a distdir";
  ok !-e "$results/Foo-Bar-1.00/root", "a link inside a distdir is dropped";
  ok !-e "$victim/.log_ref",  "no .log_ref is written through the link";
  ok -e "$victim/secret.txt", "the link target is left alone";
  ok -e "$results/Foo-Bar-1.00/index.html", "report survives ingest";
  my $out = slurp("$results/$log.out");
  like $out, qr/\broot\b/,  "build log names the link inside the distdir";
  like $out, qr/Link-1\.0/, "build log names the top-level link";
}

sub docker_module_drops_hidden_link () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  skip_all "root can list an unreadable directory" if $> == 0;
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}             = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR}     = "Foo-Bar-1.00";
  local $ENV{STUB_HIDDEN_LINK} = 1;
  delete local $ENV{CPANCOVER_COMPRESS};
  my $log = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--123.456";

  my $results = tempdir(CLEANUP => 1);
  dc("-r", $results, "cpancover-docker-module", $Dist, $log, $results);
  chmod 0755, glob "$results/*/hide $results/*/staging/*/hide";

  ok -e "$results/Foo-Bar-1.00/index.html", "the report is published";
  is links_under($results), [], "no link survives ingest";
  like slurp("$results/$log.out"), qr{/hide/root$}m,
    "build log names the hidden link";
}

sub docker_module_drops_staging_link () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  my $victim = tempdir(CLEANUP => 1);
  mkdir "$victim/Evil-1.0" or die "Can't mkdir $victim/Evil-1.0: $!";
  write_file("$victim/Evil-1.0/index.html", "html\n");
  write_file("$victim/secret.txt",          "secret\n");
  local $ENV{PATH}              = "$bin:$ENV{PATH}";
  local $ENV{STUB_STAGING_LINK} = 1;
  local $ENV{STUB_LINK_TARGET}  = $victim;
  delete local $ENV{CPANCOVER_COMPRESS};
  my $log = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--123.456";

  my $results = tempdir(CLEANUP => 1);
  dc("-r", $results, "cpancover-docker-module", $Dist, $log, $results);

  is [grep -d, glob "$results/*"], [], "no distdir is ingested";
  ok -e "$victim/Evil-1.0/index.html", "the link target keeps its distdir";
  ok -e "$victim/secret.txt",          "the link target is left alone";
  ok !-e "$victim/.log_ref", "no .log_ref is written through the link";
  ok !-e "$victim/Evil-1.0/.log_ref",
    "no .log_ref is written into the target distdir";
  is links_under($results), [], "no link survives ingest";
  like slurp("$results/$log.out"), qr{^\Q$results\E/[^/]+/staging$}m,
    "build log names the staging link";
}

sub docker_module_run_limits () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}         = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR} = "Foo-Bar-1.00";

  my $log     = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--123.456";
  my $staging = tempdir(CLEANUP => 1);
  my $work    = tempdir(CLEANUP => 1);

  {
    local $ENV{STUB_CALLS} = "$work/calls";
    dc("-r", $staging, "cpancover-docker-module", $Dist, $log, $staging);
  }

  my ($run) = grep /^run /, split /\n/, slurp("$work/calls");
  for my $flag (
    "--memory=1g",                      "--cpus=2",
    "--pids-limit=512",                 "--ulimit nofile=4096",
    "--ulimit fsize=2147483648",        "--cap-drop=ALL",
    "--security-opt=no-new-privileges", "--env TAR_OPTIONS=--no-same-owner",
    "--user cpancover",
  ) {
    like $run, qr/ \Q$flag\E /, "module container runs with $flag";
  }

  my ($cp) = grep /^cp /, split /\n/, slurp("$work/calls");
  like $cp, qr|^cp \S+:/home/cpancover/cover/staging |,
    "results are copied from the build user's home";
}

sub module_calls ($staging, %env) {
  my $work = tempdir(CLEANUP => 1);
  local $ENV{STUB_CALLS} = "$work/calls";
  local @ENV{ keys %env } = values %env;
  my $log = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--123.456";
  system "$Dc -r $staging cpancover-docker-module $Dist $log $staging"
    . " >/dev/null 2>&1";
  [split /\n/, slurp("$work/calls")]
}

sub docker_module_renders_in_second_container () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}         = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR} = "Foo-Bar-1.00";
  delete local $ENV{CPANCOVER_COMPRESS};

  my $staging = tempdir(CLEANUP => 1);
  my $calls   = module_calls($staging);

  my $create = join "\n", grep /^create /, @$calls;
  for my $flag (
    "--network none",   "--memory=2g",
    "--cpus=2",         "--pids-limit=256",
    "--cap-drop=ALL",   "--security-opt=no-new-privileges",
    "--user cpancover", "dc cpancover-render-module",
  ) {
    like $create, qr/ \Q$flag\E(?: |$)/m, "render container has $flag";
  }
  unlike $create, qr/--mount/, "render container mounts nothing";

  is grep(m{^cp \S+ \S+:/home/cpancover/input}, @$calls), 1,
    "the export is copied into the render container";
  is grep(m{^cp \S+:/home/cpancover/output }, @$calls), 1,
    "the report is copied out of the render container";

  my ($name) = $create =~ /--name[= ](\S+)/;
  my $render = join "|", map quotemeta, grep defined, "fake-render", $name;
  ok grep(/^start (?:.* )?(?:$render)$/, @$calls),
    "the render container is started";
  ok grep(/^wait (?:.* )?(?:$render)$/, @$calls),
    "the render container is waited for";

  my $dir = "$staging/Foo-Bar-1.00";
  ok -e "$dir/$_", "the published report holds $_"
    for qw( index.html cover.json assets/app.js .log_ref );
  ok !-e "$dir/$_", "the published report holds no $_"
    for qw( evil.html cover_db blib );
}

sub docker_module_render_failure_publishes_nothing () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}         = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR} = "Foo-Bar-1.00";

  my $staging = tempdir(CLEANUP => 1);
  module_calls($staging, STUB_NO_RENDER => 1);

  ok !-e "$staging/Foo-Bar-1.00", "no report is published";
  my $log = "$staging/P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--123.456.out";
  like slurp($log), qr/^\Q[dc] render produced no report\E/m,
    "build log notes the missing report";
}

sub docker_module_render_timeout () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}         = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR} = "Foo-Bar-1.00";

  my $staging = tempdir(CLEANUP => 1);
  my $calls   = module_calls(
    $staging,
    CPANCOVER_RENDER_TIMEOUT => 1,
    STUB_RENDER_WAIT_SLEEP   => 5,
  );

  my ($name) = map /--name[= ](\S+)/, grep /^create /, @$calls;

  ok defined $name, "the render container is named";
  ok grep(/^kill (?:.* )?\Q$name\E$/, @$calls),
    "the render container is killed";
  my $log = "$staging/P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--123.456.out";
  like slurp($log), qr/^\Q[dc] render timed out after 1s\E$/m,
    "build log notes the render timeout";
}

sub docker_module_rejects_large_export () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}         = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR} = "Foo-Bar-1.00";

  my $staging = tempdir(CLEANUP => 1);
  my $calls   = module_calls($staging, CPANCOVER_EXPORT_MAX_MB => 0);

  is grep(/^create /, @$calls), 0, "no render container is created";
  ok !-e "$staging/Foo-Bar-1.00", "no report is published";
  my $log = "$staging/P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--123.456.out";
  like slurp($log), qr/^\Q[dc] export of\E/m, "build log notes the export size";
}

sub build_environment () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}         = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR} = "Foo-Bar-1.00";
  my @vars = qw(
    AUTOMATED_TESTING NONINTERACTIVE_TESTING EXTENDED_TESTING
    PERL_MM_USE_DEFAULT
  );
  delete local $ENV{$_} for @vars;

  my $log     = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--123.456";
  my $staging = tempdir(CLEANUP => 1);
  my $work    = tempdir(CLEANUP => 1);

  {
    local $ENV{STUB_CALLS} = "$work/calls";
    dc("-r", $staging, "cpancover-docker-module", $Dist, $log, $staging);
  }

  my ($env) = grep /^env /, split /\n/, slurp("$work/calls");
  like $env, qr/ \Q$_\E=1\b/, "build runs with $_=1" for @vars;
}

sub force_retries_failed_only () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}         = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR} = "Foo-Bar-1.00";
  my $module = "P/PJ/PJCJ/Foo-Bar-1.00.tar.gz";
  my $work   = tempdir(CLEANUP => 1);

  my $covered = tempdir(CLEANUP => 1);

  mkdir "$covered/Foo-Bar-1.00" or die "Can't mkdir $covered/Foo-Bar-1.00: $!";
  write_file("$covered/Foo-Bar-1.00/cover.json", "{}\n");
  {
    local $ENV{STUB_CALLS} = "$work/covered.calls";
    dc("-f", "-r", $covered, "cpancover", "--build", $module);
  }
  ok !-e "$work/covered.calls", "no docker build for a covered dist";

  my $failed = tempdir(CLEANUP => 1);
  mkdir "$failed/__failed__" or die "Can't mkdir $failed/__failed__: $!";
  write_file("$failed/__failed__/Foo-Bar-1.00", "1234567890\n");
  {
    local $ENV{STUB_CALLS} = "$work/failed.calls";
    dc("-f", "-r", $failed, "cpancover", "--build", $module);
  }
  like slurp("$work/failed.calls"), qr/\brun\b/,
    "forced build retries a failed dist";
  ok -e "$failed/Foo-Bar-1.00/cover.json", "retried dist is ingested";
}

sub stale_report_outcomes () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}         = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR} = "Foo-Bar-1.00";
  my $module = "P/PJ/PJCJ/Foo-Bar-1.00.tar.gz";

  my $stale = tempdir(CLEANUP => 1);
  mkdir "$stale/Foo-Bar-1.00" or die "Can't mkdir $stale/Foo-Bar-1.00: $!";
  write_file("$stale/Foo-Bar-1.00/cover.json", "{}\n");
  write_file("$stale/Foo-Bar-1.00/index.html", "old\n");
  my $old = time - 3600;
  utime $old, $old, "$stale/Foo-Bar-1.00/cover.json" or die "Can't utime: $!";
  {
    local $ENV{STUB_NO_DIST} = 1;
    dc(
      "-r",        $stale,            "cpancover", "--build",
      "--rebuild", "--rebuild_batch", 0,           $module,
    );
  }
  ok -e "$stale/__failed__/Foo-Bar-1.00",
    "a rebuild that produces nothing marks the dist failed";
  ok -e "$stale/__rebuilt__/Foo-Bar-1.00", "and marks it rebuilt";
  is slurp("$stale/Foo-Bar-1.00/index.html"), "old\n",
    "the old report survives";

  dc("-f", "-r", $stale, "cpancover", "--build", $module);
  ok !-e "$stale/__failed__/Foo-Bar-1.00",
    "a forced retry that produces a report clears the failed marker";
  is slurp("$stale/Foo-Bar-1.00/index.html"), "html\n",
    "and replaces the old report";
}

sub cpancover_leaves_build_alone () {
  skip_all "timeout required" if system "command -v timeout >/dev/null 2>&1";
  my $bundle = "blib/arch/auto/Devel/Cover/Cover.$Config{dlext}";
  skip_all "build artefacts missing - run after `make`" unless -f $bundle;

  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH}         = "$bin:$ENV{PATH}";
  local $ENV{STUB_DISTDIR} = "Foo-Bar-1.00";
  my $module  = "P/PJ/PJCJ/Foo-Bar-1.00.tar.gz";
  my $covered = tempdir(CLEANUP => 1);
  mkdir "$covered/Foo-Bar-1.00" or die "Can't mkdir $covered/Foo-Bar-1.00: $!";
  write_file("$covered/Foo-Bar-1.00/cover.json", "{}\n");

  my @before = (stat $bundle)[1, 9];
  dc("-r", $covered, "cpancover", "--build", $module);
  my @after = (stat $bundle)[1, 9];

  is \@after, \@before, "cpancover does not rebuild an up-to-date checkout";
}

sub controller_rebuild_module_recipe () {
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH} = "$bin:$ENV{PATH}";
  my $module = "P/PJ/PJCJ/Foo-Bar-1.00.tar.gz";
  my $work   = tempdir(CLEANUP => 1);
  my $dir    = tempdir(CLEANUP => 1);

  {
    local $ENV{STUB_CALLS} = "$work/calls";
    dc("-e", "dev", "-r", $dir, "cpancover-controller-rebuild-module", $module,
    );
  }

  my $calls = slurp("$work/calls");
  like $calls, qr{\brun\b.* pjcj/cpancover_dev }, "runs the dev image";
  like $calls, qr{--label cpancover\.env=dev},    "container is labelled";
  like $calls, qr{--memory=8g},
    "controller gets enough memory for HTML generation";
  like $calls, qr{source=\Q$dir\E,target=/remote_staging},
    "results dir is mounted";
  like $calls, qr{ dc --env dev cpancover-rebuild-module \Q$module\E},
    "runs the inner rebuild-module recipe";
}

sub controller_staging_on_host () {
  my $bin = tempdir(CLEANUP => 1);
  make_docker_stub($bin);
  local $ENV{PATH} = "$bin:$ENV{PATH}";
  my $module = "P/PJ/PJCJ/Foo-Bar-1.00.tar.gz";
  my $work   = tempdir(CLEANUP => 1);
  my $home   = tempdir(CLEANUP => 1);

  {
    local $ENV{STUB_CALLS} = "$work/calls";
    local $ENV{HOME}       = $home;
    dc("-e", "dev", "cpancover-controller-rebuild-module", $module);
  }

  like slurp("$work/calls"),
    qr{source=\Q$home\E/cover/staging_dev,target=/remote_staging},
    "host run mounts the staging dir, even with containers running";
}

sub docker_rm_recipe () {
  my $bin = tempdir(CLEANUP => 1);
  write_file("$bin/docker", <<~'SH');
    #!/bin/sh
    cmd="$1"
    shift
    case "$cmd" in
      ps)
        echo "CONTAINER ID IMAGE COMMAND CREATED STATUS NAMES"
        echo "abc123 img cmd 1 hour ago Up old-controller"
        ;;
      rm)
        echo "rm $*" >>"$STUB_CALLS"
        for id; do :; done
        echo "$id"
        ;;
    esac
    exit 0
    SH
  chmod 0755, "$bin/docker" or die "Can't chmod docker stub: $!";
  my $work = tempdir(CLEANUP => 1);
  local $ENV{PATH}       = "$bin:$ENV{PATH}";
  local $ENV{STUB_CALLS} = "$work/calls";

  my $out = `$Dc -e dev cpancover-docker-rm`;
  is $out, "", "the recipe prints no container ids";
  like slurp("$work/calls"), qr/^rm -f abc123$/m,
    "the recipe removes the listed container";
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

sub make_caddy_stub ($bin) {
  write_file("$bin/caddy", <<~'SH');
    #!/bin/sh
    echo "$*" >>"${STUB_CALLS:-/dev/null}"
    cmd="$1"
    shift
    case "$cmd" in
      validate)
        cfg=
        while [ $# -gt 0 ]; do
          [ "$1" = "--config" ] && cfg="$2"
          shift
        done
        cat "$cfg" >>"${STUB_CADDY_CFG:-/dev/null}"
        if grep -q "output file" "$cfg"; then
          echo "mkdir /var/log/caddy: permission denied" >&2
          exit 1
        fi
        ;;
    esac
    exit 0
    SH
  chmod 0755, "$bin/caddy" or die "Can't chmod caddy stub: $!";
}

sub check_caddy_recipe () {
  my $bin = tempdir(CLEANUP => 1);
  make_caddy_stub($bin);
  local $ENV{PATH} = "$bin:$ENV{PATH}";
  my $work = tempdir(CLEANUP => 1);
  my $base = tempdir(CLEANUP => 1);
  mkdir "$base/$_"
    or die "Can't mkdir $base/$_: $!"
    for "data", "data/cover", "data/cover/staging", "data/cover/www";
  symlink "$base/data/cover", "$base/cover"
    or die "Can't symlink $base/cover: $!";

  my $out;
  {
    local $ENV{STUB_CALLS}     = "$work/calls";
    local $ENV{STUB_CADDY_CFG} = "$work/cfg";
    $out = qx($Dc -r "$base/cover/staging" cpancover-check-caddy 2>&1);
  }
  is $?, 0, "check-caddy succeeds without root" or diag $out;

  my $cfg  = slurp("$work/cfg");
  my $root = realpath("$base/data/cover/www");
  like $cfg, qr{^\s*root \* \Q$root\E$}m,
    "web root is canonicalised through symlinks";
  like $cfg,   qr{output discard},       "validation copy discards the log";
  unlike $cfg, qr{output file},          "validation copy has no log file";
  like slurp("$work/calls"), qr{^fmt }m, "generated config is formatted";

  unless (-e "/etc/caddy/Caddyfile") {
    like $out, qr{no installed Caddyfile}i, "missing installed file reported";
    like $out, qr{output file /var/log/caddy/cpancover\.com\.log},
      "returned config keeps the real log output";
  }
}

sub check_caddy_root_fallback () {
  my $bin = tempdir(CLEANUP => 1);
  make_caddy_stub($bin);
  local $ENV{PATH} = "$bin:$ENV{PATH}";
  my $work = tempdir(CLEANUP => 1);
  my $base = tempdir(CLEANUP => 1);

  {
    local $ENV{STUB_CADDY_CFG} = "$work/cfg";
    my $out = qx($Dc -r "$base/missing/staging" cpancover-check-caddy 2>&1);
    is $?, 0, "check-caddy succeeds with a nonexistent results dir"
      or diag $out;
  }
  like slurp("$work/cfg"), qr{^\s*root \* \Q$base\E/missing/staging/\.\./www$}m,
    "web root falls back to the literal path";
}

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

my $Dc_abs = realpath $Dc;

sub make_gold_tree ($installed, $full) {
  my $dir = tempdir(CLEANUP => 1);
  mkdir "$dir/$_"
    or die "Can't mkdir $dir/$_: $!"
    for "utils", "test_output", "test_output/cover";
  write_file("$dir/test_output/cover/foo.5.020000", "gold\n");
  write_file("$dir/utils/all_versions",             <<~SH);
    #!/bin/sh
    case "\$*" in
    "--list --force") echo "Versions: $full" ;;
    "--list") echo "Versions: $installed" ;;
    *) echo "\$@" >>args.log ;;
    esac
    SH
  chmod 0755, "$dir/utils/all_versions"
    or die "Can't chmod $dir/utils/all_versions: $!";
  $dir
}

sub dc_in ($dir, @args) {
  my $cmd = join " ", $Dc_abs, @args;
  my $out = `cd $dir && $cmd 2>&1`;
  ($out, $? >> 8)
}

sub all_gold_partial_machine () {
  my $dir = make_gold_tree("5.20.0", "5.20.0 5.44.0");
  my ($out, $exit) = dc_in($dir, "all-gold", "foo");
  isnt $exit, 0, "a partial machine refuses to run";
  ok -e "$dir/test_output/cover/foo.5.020000", "the golden file survives";
  like $out, qr/5\.44\.0/, "the missing version is named";
}

sub all_gold_full_machine () {
  my $dir = make_gold_tree("5.20.0 5.44.0", "5.20.0 5.44.0");
  my ($out, $exit) = dc_in($dir, "all-gold", "foo");
  is $exit, 0, "a full machine proceeds" or diag $out;
  ok !-e "$dir/test_output/cover/foo.5.020000", "the golden file is removed";
  like slurp("$dir/args.log"), qr/^make gold TEST=foo$/m,
    "gold regeneration runs";
}

sub all_gold_forced () {
  my $dir = make_gold_tree("5.20.0", "5.20.0 5.44.0");
  my ($out, $exit) = dc_in($dir, "-f", "all-gold", "foo");
  is $exit, 0, "--force overrides the guard" or diag $out;
  like slurp("$dir/args.log"), qr/^make gold TEST=foo$/m,
    "gold regeneration runs under force";
}

sub make_build_stubs ($bin) {
  write_file("$bin/$_", <<~'SH') for qw( make perl );
    #!/bin/sh
    echo "$*" >>"$STUB_CALLS"
    echo 1
    SH
  chmod 0755, "$bin/make", "$bin/perl" or die "Can't chmod build stubs: $!";
}

sub cpancover_call ($recipe, %env) {
  my $bin  = tempdir(CLEANUP => 1);
  my $work = tempdir(CLEANUP => 1);
  make_build_stubs($bin);
  local $ENV{PATH}        = "$bin:$ENV{PATH}";
  local $ENV{STUB_CALLS}  = "$work/calls";
  local @ENV{ keys %env } = values %env;
  my ($out, $exit) = dc_in($work, "-r", "$work/results", @$recipe);
  is $exit, 0, "@$recipe succeeds" or diag $out;
  my $calls  = -e "$work/calls" ? slurp("$work/calls") : "";
  my ($call) = grep m|bin/cpancover --local |, split /\n/, $calls;
  $call // ""
}

sub build_module_exports () {
  my $call = cpancover_call(["cpancover-build-module", $Dist]);
  like $call,   qr/ --local_build /,      "the module is built";
  like $call,   qr/ --export \Q$Dist\E$/, "the build is exported";
  unlike $call, qr/ --render /,           "the build is not rendered";
}

sub render_module_copies_input () {
  my $home = tempdir(CLEANUP => 1);
  mkdir "$home/input" or die "Can't mkdir $home/input: $!";
  write_file("$home/input/cover.json", "{}\n");
  my $call = cpancover_call(["cpancover-render-module"], HOME => $home);
  like $call, qr| --render \Q$home\E/work \Q$home\E/output$|,
    "the render reads a copy of the input";
  is slurp("$home/work/cover.json"), "{}\n", "the copy holds the input";
  ok -d "$home/output", "the output dir is created";
}

sub main () {
  my @tests = qw(
    compress_recipe
    uncompress_recipe
    docker_module_log_ref
    docker_module_timeout_log_ref
    docker_module_replaces_failed
    docker_module_ingests_only_distdir
    docker_module_drops_symlinks
    docker_module_drops_hidden_link
    docker_module_drops_staging_link
    docker_module_run_limits
    docker_module_renders_in_second_container
    docker_module_render_failure_publishes_nothing
    docker_module_render_timeout
    docker_module_rejects_large_export
    build_environment
    force_retries_failed_only
    stale_report_outcomes
    cpancover_leaves_build_alone
    controller_rebuild_module_recipe
    controller_staging_on_host
    docker_rm_recipe
    seed_recipe
    check_caddy_recipe
    check_caddy_root_fallback
    all_gold_partial_machine
    all_gold_full_machine
    all_gold_forced
    build_module_exports
    render_module_copies_input
  );
  for my $test (@tests) {
    no strict qw( refs );
    subtest $test => \&$test;
  }
  done_testing;
}

main;

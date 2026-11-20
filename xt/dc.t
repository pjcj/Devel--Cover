#!/usr/bin/perl
# HARNESS-DURATION-LONG

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.42.0;

use Test2::V0   qw( diag done_testing is isnt like ok skip_all subtest unlike );
use Config      qw( %Config );
use Cwd         qw( realpath );
use File::Find  qw( find );
use File::Temp  qw( tempdir );
use List::Util  qw( sum );
use Time::HiRes qw( lstat );

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

sub write_top_level_files ($dir) {
  mkdir "$dir/dist" or die "Can't mkdir $dir/dist: $!";
  write_file("$dir/$Log", "log\n");
  write_file("$dir/$_",   "x\n")
    for qw( index.html about.html collection.css collection.js );
  write_file("$dir/cpancover.json", "{}");
  write_file("$dir/dist/F.html",    "html\n");
  write_file("$dir/index.html.gz",  "stale\n");
  write_file("$dir/dist/F.html.gz", "stale\n");
}

sub make_results_tree () {
  my $dir = tempdir(CLEANUP => 1);
  for my $d ("Foo-Bar-1.00", "Foo-Bar-1.00/runs") {
    mkdir "$dir/$d" or die "Can't mkdir $dir/$d: $!";
  }
  write_file("$dir/Foo-Bar-1.00/cover.json", "{}");
  write_file("$dir/Foo-Bar-1.00/index.html", "html\n");
  write_file("$dir/Foo-Bar-1.00/cover.14",   "db\n");
  write_top_level_files($dir);
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

my @Report_files = qw( index.html lib-One-pm.html cover.json .log_ref
  assets/app.js );

sub make_compressed_tree (@names) {
  my $dir = tempdir(CLEANUP => 1);
  for my $name (@names) {
    mkdir "$dir/$_" or die "Can't mkdir $dir/$_: $!" for $name, "$name/assets";
    write_file("$dir/$name/$_", "$name/$_\n") for @Report_files;
  }
  write_top_level_files($dir);
  dc("-r", $dir, "cpancover-compress");
  $dir
}

sub write_gz ($path, $content) {
  write_file($path, $content);
  system("gzip", $path) == 0 or die "Can't gzip $path";
}

sub top_level_leftovers ($dir) {
  opendir my $dh, $dir or die "Can't opendir $dir: $!";
  my @left = grep /\.gz$|^\.uncompress-|^virtual_unzipped$/, readdir $dh;
  closedir $dh;
  \@left
}

sub uncompress_tree_recipe () {
  my @old = qw( Old-One-1.00 Old-Two-2.00 );
  my $dir = make_compressed_tree(@old);
  my $one = "$dir/Old-One-1.00";
  my $two = "$dir/Old-Two-2.00";
  my $new = "$dir/New-Three-3.00";

  mkdir $new or die "Can't mkdir $new: $!";
  write_file("$new/index.html", "new\n");
  write_file("$new/cover.json", "{}");
  my $new_inode = inode("$new/index.html");

  unlink("$two/index.html", "$two/virtual_unzipped") == 2
    or die "Can't unlink in $two: $!";
  my $tmp_page = "$one/index.html.uncompress-tmp";
  write_file($tmp_page, "tmp page\n");
  my $gz    = "$one/lib-One-pm.html.gz";
  my $mtime = time - 86_400;
  utime $mtime, $mtime, $gz or die "Can't utime $gz: $!";
  chmod 0640, $gz or die "Can't chmod $gz: $!";

  my $outside = tempdir(CLEANUP => 1);
  write_gz("$outside/page.html", "outside\n");
  write_file("$outside/virtual_unzipped", "");
  link "$outside/virtual_unzipped", "$outside/page.html"
    or die "Can't link $outside/page.html: $!";
  symlink $outside, "$dir/Link-1.00" or die "Can't symlink $dir/Link-1.00: $!";
  mkdir "$dir/__failed__" or die "Can't mkdir $dir/__failed__: $!";
  my @kept = ($outside, "$dir/dist", "$dir/__failed__", "$one/assets");
  write_gz("$_/page.html", "kept\n") for @kept[1 .. 3];

  my $out = qx($Dc -r "$dir" cpancover-uncompress 2>&1);
  is $?, 0, "uncompress succeeds" or diag $out;
  for my $name (@old) {
    is slurp("$dir/$name/$_"), "$name/$_\n", "$name/$_ holds its text"
      for @Report_files;
    is top_level_leftovers("$dir/$name"), [], "$name holds no gzip files";
  }
  is slurp($tmp_page), "tmp page\n",
    "a page named like a temporary file keeps its text";
  my @stat = stat "$one/lib-One-pm.html";
  is $stat[9], $mtime, "the page keeps the mtime of its gzip file";
  is sprintf("%04o", $stat[2] & 07777), "0640",
    "the page keeps the mode of its gzip file";
  ok -e "$dir/$Log.gz", "the top-level log stays compressed";
  ok !-e "$dir/$Log",   "no plain top-level log appears";
  is inode("$new/index.html"), $new_inode, "a plain report keeps its inode";
  is slurp("$new/index.html"), "new\n",    "a plain report keeps its text";
  ok -e "$_/page.html.gz",           "$_/page.html.gz is left alone" for @kept;
  ok -z "$outside/page.html",        "the page outside the tree stays empty";
  ok -e "$outside/virtual_unzipped", "the marker outside the tree is kept";
  like $out, qr/converted 4 files in 2 directories/, "the counts are reported";
  unlike $out, qr/^find:/m,                          "find reports no errors";

  $out = qx($Dc -r "$dir" cpancover-uncompress 2>&1);
  is $?, 0, "a second uncompress succeeds" or diag $out;
  like $out, qr/converted 0 files in 0 directories/,
    "a second uncompress converts nothing";
  for my $name (@old) {
    is slurp("$dir/$name/$_"), "$name/$_\n", "$name/$_ keeps its text"
      for @Report_files;
  }

  $out = qx($Dc -r "$dir/cpancover.json" cpancover-uncompress 2>&1);
  isnt $?, 0, "uncompress fails when the results dir is not a directory"
    or diag $out;
}

sub replace_page ($page, $content) {
  unlink $page or die "Can't unlink $page: $!";
  write_file($page, $content);
}

sub run_uncompress ($dir, @opts) {
  my $out = qx($Dc @opts -r "$dir" cpancover-uncompress 2>&1);
  ($out, $?)
}

sub warns ($out, $path) { $out =~ /\[WARNING\].*\Q$path\E(?![\w.-])/ }

sub uncompress_tree_leaves_bad_pages () {
  my $dir     = make_compressed_tree(qw( Corrupt-1.00 Differ-1.00 Zz-1.00 ));
  my $corrupt = "$dir/Corrupt-1.00";
  my $differ  = "$dir/Differ-1.00";
  write_file("$corrupt/index.html.gz", "not gzip");
  replace_page("$differ/index.html", "other\n");

  my ($out, $status) = run_uncompress($dir);
  isnt $status, 0, "uncompress fails with bad pages" or diag $out;
  is slurp("$corrupt/index.html.gz"), "not gzip",
    "the corrupt file keeps its bytes";
  ok -z "$corrupt/index.html",       "the page of the corrupt file stays empty";
  ok -e "$corrupt/virtual_unzipped", "its report keeps the marker";
  is [grep /^\.uncompress-/, top_level_leftovers($corrupt)->@*], [],
    "no temporary file remains";
  ok warns($out, "Corrupt-1.00/index.html.gz"),
    "the output names the corrupt file";
  is slurp("$corrupt/lib-One-pm.html"), "Corrupt-1.00/lib-One-pm.html\n",
    "the other page of its report holds its text";
  is slurp("$dir/Zz-1.00/$_"), "Zz-1.00/$_\n", "a later report holds $_"
    for @Report_files;
  is slurp("$differ/index.html"), "other\n", "a different page keeps its text";
  ok -e "$differ/index.html.gz", "a different page keeps its gzip file";
  ok warns($out, "Differ-1.00/index.html.gz"),
    "the output names the different page";
  like $out, qr/converted 4 files in 3 directories/,
    "the output reports the counts";
  like $out, qr/\[WARNING\].*left 2 gzip files in place/,
    "the output counts the files left";
}

sub uncompress_tree_leaves_linked_pages () {
  my $outside = tempdir(CLEANUP => 1);
  mkdir "$outside/empty" or die "Can't mkdir $outside/empty: $!";
  write_file("$outside/empty.html", "");
  my $links = {
    "Link-Dir-1.00"     => "$outside/empty",
    "Link-File-1.00"    => "$outside/empty.html",
    "Link-Missing-1.00" => "$outside/missing.html",
  };
  my @names = sort keys %$links;
  my $dir   = make_compressed_tree(@names);
  for my $name (@names) {
    my $page = "$dir/$name/index.html";
    unlink $page or die "Can't unlink $page: $!";
    symlink $links->{$name}, $page or die "Can't symlink $page: $!";
  }

  my ($out, $status) = run_uncompress($dir);
  isnt $status, 0, "uncompress fails with linked pages" or diag $out;
  for my $name (@names) {
    my $page = "$dir/$name/index.html";
    is readlink $page, $links->{$name}, "the page of $name stays a link";
    ok -e "$page.gz", "$name keeps its gzip file";
    ok warns($out, "$name/index.html.gz"),
      "the output names the linked page of $name";
  }
  opendir my $dh, "$outside/empty" or die "Can't opendir $outside/empty: $!";
  is [grep !/^\.\.?$/, readdir $dh], [], "the directory outside stays empty";
  ok -z "$outside/empty.html",    "the file outside stays empty";
  ok !-e "$outside/missing.html", "the missing file stays missing";
  like $out, qr/\[WARNING\].*left 3 gzip files in place/,
    "the output counts the files left";
}

sub uncompress_tree_leaves_read_only_dir () {
  skip_all "root can write into a read-only directory" unless $>;
  my $dir  = make_compressed_tree("Read-Only-1.00");
  my $read = "$dir/Read-Only-1.00";
  chmod 0555, $read or die "Can't chmod $read: $!";
  my ($out, $status) = run_uncompress($dir);
  chmod 0755, $read or die "Can't chmod $read: $!";

  isnt $status, 0, "uncompress fails with a read-only directory" or diag $out;
  for my $page (qw( index.html lib-One-pm.html )) {
    ok -e "$read/$page.gz", "$page.gz remains";
    ok -z "$read/$page",    "$page stays empty";
  }
  like $out, qr|\[WARNING\].*Read-Only-1\.00/\S+\.gz|,
    "the output names a file of the directory";
  like $out, qr/converted 0 files in 0 directories/,
    "the output reports the counts";
}

sub uncompress_tree_empty_and_equal_pages () {
  my $dir   = make_compressed_tree(qw( Empty-1.00 Equal-1.00 ));
  my $empty = "$dir/Empty-1.00";
  my $equal = "$dir/Equal-1.00";
  unlink "$empty/index.html.gz" or die "Can't unlink $empty/index.html.gz: $!";
  replace_page("$equal/index.html", "Equal-1.00/index.html\n");

  my ($out, $status) = run_uncompress($dir);
  is $status, 0, "uncompress succeeds with empty and equal pages" or diag $out;
  ok -z "$empty/index.html", "a page with no gzip file stays empty";
  ok warns($out, "Empty-1.00/index.html"),
    "the output names the page with no text";
  ok -e "$empty/virtual_unzipped", "its report keeps the marker";
  is slurp("$equal/index.html"), "Equal-1.00/index.html\n",
    "an equal page keeps its text";
  ok !-e "$equal/index.html.gz",
    "uncompress deletes the gzip file of an equal page";
  unlike $out, qr/\[WARNING\].*Equal-1\.00/, "an equal page gets no warning";
  ok !-e "$equal/virtual_unzipped",
    "uncompress deletes the marker of a finished report";
  like $out, qr/converted 3 files in 2 directories/,
    "an equal page counts as converted";
}

sub messages ($out) {
  map /\[(\w+)\]\s+\S+: (.*)/ ? "$1 $2" : (), split /\n/, $out
}

sub uncompress_tree_index_pages () {
  my @old = qw( Corrupt-Index-1.00 Empty-Index-1.00 Gz-Only-1.00 );
  my $dir = make_compressed_tree(@old);
  my ($corrupt, $empty, $gz_only) = map "$dir/$_", @old;
  unlink "$gz_only/index.html"  or die "Can't unlink $gz_only/index.html: $!";
  unlink "$empty/index.html.gz" or die "Can't unlink $empty/index.html.gz: $!";
  write_file("$corrupt/index.html.gz", "not gzip");
  for my $name (qw( Plain-1.00 Plain-Index-1.00 )) {
    mkdir "$dir/$name" or die "Can't mkdir $dir/$name: $!";
    write_file("$dir/$name/cover.json", "{}");
  }
  write_file("$dir/Plain-Index-1.00/index.html", "plain\n");

  my ($out, $status) = run_uncompress($dir);
  isnt $status, 0, "uncompress fails with a corrupt index page" or diag $out;
  is slurp("$gz_only/index.html"), "Gz-Only-1.00/index.html\n",
    "a lone index.html.gz becomes the index page";
  my $want = [
    "INFO Gz-Only-1.00: index.html.gz had no index.html",
    "WARNING Corrupt-Index-1.00: index.html is empty, index.html.gz left",
    "WARNING Empty-Index-1.00: index.html is empty",
    "WARNING Plain-1.00: no index.html",
    "INFO 1 directories had index.html.gz with no index.html"
      . " and 3 have no index page",
    "INFO converted 4 files in 3 directories",
    "WARNING left 1 gzip files in place",
  ];
  my @lines = messages($out);
  is [@lines[-@$want .. -1]], $want,
    "the output lists the index pages after the pass"
    or diag $out;
}

sub tree_state ($dir) {
  my $state = {};
  find(
    {
      wanted   => sub { $state->{$_} = join " ", (lstat)[1, 7, 9] },
      no_chdir => 1,
    },
    $dir,
  );
  $state
}

sub dry_run_then_run ($dir) {
  my $before = tree_state($dir);
  my ($dry, $dry_status) = run_uncompress($dir, "-d");
  my $after = tree_state($dir);
  is $after, $before, "the dry run changes nothing in the tree";
  is [grep m|/\.uncompress-[^/]*$|, keys %$after], [],
    "the dry run makes no temporary file";
  my ($out, $status) = run_uncompress($dir);
  is $status, $dry_status, "the dry run exits as the run does" or diag $dry;
  my ($would) = $dry =~ /would convert (\d+ files in \d+ directories),/;
  my ($done)  = $out =~ /\bconverted (\d+ files in \d+ directories)/;
  is $done, $would, "the run converts what the dry run counts";
  is [grep /^WARNING/, messages($dry)], [grep /^WARNING/, messages($out)],
    "the dry run gives the warnings of the run";
  ($dry, $out, $status)
}

sub index_lines ($out) { [grep /index\.html/, messages($out)] }

sub uncompress_tree_dry_run () {
  my $dir   = make_compressed_tree(qw( Dry-One-1.00 Dry-Two-2.00 ));
  my $equal = "Dry-Two-2.00/index.html";
  replace_page("$dir/$equal", "$equal\n");
  my @plain = qw( Dry-One-1.00/index.html Dry-One-1.00/lib-One-pm.html
    Dry-Two-2.00/lib-One-pm.html );
  my $bytes = sum map length "$_\n", @plain;

  my $before = tree_state($dir);
  my ($out, $status) = run_uncompress($dir, "-d");
  is $status, 0, "a dry run succeeds" or diag $out;
  like $out,
    qr/would convert 4 files in 2 directories, $bytes bytes as plain files/,
    "the dry run counts the pages, the directories and the bytes";
  is tree_state($dir), $before, "a dry run changes nothing in the tree";

  my $corrupt = "Dry-One-1.00/lib-One-pm.html.gz";
  write_file("$dir/$corrupt", "not gzip");
  $before = tree_state($dir);
  ($out, $status) = run_uncompress($dir, "-d");
  isnt $status, 0, "a dry run fails with a corrupt file" or diag $out;
  ok warns($out, $corrupt), "the dry run names the corrupt file";
  is tree_state($dir), $before, "a dry run leaves the corrupt file alone";

  $dir = make_compressed_tree(qw( Empty-Index-1.00 Gz-Only-1.00 ));
  for my $page ("Empty-Index-1.00/index.html.gz", "Gz-Only-1.00/index.html") {
    unlink "$dir/$page" or die "Can't unlink $dir/$page: $!";
  }
  mkdir "$dir/Plain-1.00" or die "Can't mkdir $dir/Plain-1.00: $!";
  my ($dry, $run) = dry_run_then_run($dir);
  like $dry, qr/would convert 3 files in 2 directories,/,
    "the dry run counts a fresh tree";
  my $lines = index_lines($run);
  ok grep(/and 2 have no index page$/, @$lines), "the run lists index pages";
  is index_lines($dry), $lines, "the dry run lists the index pages of the run"
    or diag $dry;
}

sub uncompress_tree_odd_pages () {
  my @old = qw( Long-1.00 Read-Only-Gz-1.00 Tmp-Name-1.00 );
  my $dir = make_compressed_tree(@old);
  my ($long, $read, $tmp) = map "$dir/$_", @old;
  my $long_page = "$long/" . "p" x 245 . ".html";
  write_gz($long_page, "long\n");
  my $gz    = "$read/lib-One-pm.html.gz";
  my $mtime = time - 86_400;
  utime $mtime, $mtime, $gz or die "Can't utime $gz: $!";
  chmod 0444, $gz or die "Can't chmod $gz: $!";
  my $tmp_page = "$tmp/lib-One-pm.html.uncompress-tmp";
  write_gz($tmp_page, "tmp page\n");

  my (undef, $out, $status) = dry_run_then_run($dir);
  is $status, 0, "uncompress succeeds with odd pages" or diag $out;
  like $out, qr/converted 8 files in 3 directories/, "the run counts the pages";
  unlike $out, qr/\[WARNING\]/, "the output has no warning";
  is slurp($long_page), "long\n", "a page with a long name holds its text";
  my $page = "$read/lib-One-pm.html";
  is slurp($page), "Read-Only-Gz-1.00/lib-One-pm.html\n",
    "the page of a read-only gzip file holds its text";
  my @stat = stat $page;
  is $stat[9], $mtime, "the page keeps the mtime of its read-only gzip file";
  is sprintf("%04o", $stat[2] & 07777), "0444", "the page stays read-only";
  is slurp($tmp_page), "tmp page\n",
    "a page named like a temporary file holds its text";
  is slurp("$tmp/lib-One-pm.html"), "Tmp-Name-1.00/lib-One-pm.html\n",
    "the page with the shorter name holds its own text";
  is top_level_leftovers("$dir/$_"), [], "$_ holds no gzip or temporary files"
    for @old;
}

sub gzip_bytes ($content) {
  my $dir = tempdir(CLEANUP => 1);
  write_gz("$dir/page", $content);
  slurp("$dir/page.gz")
}

sub uncompress_odd_report ($name, $left, $setup) {
  my $dir    = make_compressed_tree($name);
  my $report = "$dir/$name";
  $setup->($report);
  my (undef, $out, $status) = dry_run_then_run($dir);
  isnt $status, 0, "uncompress fails in $name" or diag $out;
  is slurp("$report/$_"), "$name/$_\n", "$name/$_ holds its text"
    for @Report_files;
  like $out, qr/\[WARNING\].*left $left gzip files in place/,
    "the output counts the entries left in $name";
  ($report, $out)
}

sub uncompress_tree_leaves_marker_page () {
  my $gz = gzip_bytes("secret page");
  my ($report, $out) = uncompress_odd_report(
    "Marker-1.00", 1,
    sub ($report) { write_file("$report/virtual_unzipped.gz", $gz) },
  );
  is slurp("$report/virtual_unzipped.gz"), $gz,
    "the gzip file of the marker keeps its bytes";
  ok -z "$report/virtual_unzipped", "the marker remains and stays empty";
  ok warns($out, "Marker-1.00/virtual_unzipped.gz"),
    "the output names the gzip file of the marker";
}

sub link_marker ($report, @pages) {
  link "$report/virtual_unzipped", "$report/$_"
    or die "Can't link $report/$_: $!"
    for @pages;
}

sub uncompress_tree_leaves_double_suffixes () {
  my $bytes
    = { a => gzip_bytes(gzip_bytes("inner text")), b => gzip_bytes("single") };
  my @pages = sort keys %$bytes;
  my ($report, $out) = uncompress_odd_report(
    "Double-1.00",
    4,
    sub ($report) {
      write_file("$report/$_.gz.gz", $bytes->{$_}) for @pages;
      link_marker($report, map "$_.gz", @pages);
    },
  );
  for my $page (@pages) {
    is slurp("$report/$page.gz.gz"), $bytes->{$page},
      "$page.gz.gz keeps its bytes";
    ok -z "$report/$page.gz",                  "$page.gz stays empty";
    ok !-e "$report/$page",                    "no page $page appears";
    ok warns($out, "Double-1.00/$page.gz.gz"), "the output names $page.gz.gz";
  }
}

sub uncompress_tree_leaves_gz_links () {
  my $outside = tempdir(CLEANUP => 1);
  my $target  = "$outside/evil.html.gz";
  my $gz      = gzip_bytes("evil\n");
  write_file($target, $gz);
  my $links
    = { "evil.html.gz" => $target, "gone.html.gz" => "$outside/gone.html.gz" };
  my @links = sort keys %$links;
  my ($report, $out) = uncompress_odd_report(
    "Links-1.00",
    2,
    sub ($report) {
      for my $link (@links) {
        symlink $links->{$link}, "$report/$link"
          or die "Can't symlink $report/$link: $!";
      }
      link_marker($report, qw( evil.html gone.html ));
    },
  );
  for my $link (@links) {
    is readlink "$report/$link", $links->{$link}, "$link stays a link";
    ok warns($out, "Links-1.00/$link"), "the output names $link";
  }
  is slurp($target), $gz, "the gzip file outside keeps its bytes";
  ok -z "$report/evil.html",        "the page beside the link stays empty";
  ok -e "$report/virtual_unzipped", "the marker remains";
  ok !warns($out, "Links-1.00/gone.html"),
    "the page beside a broken link gets no second warning";
}

sub uncompress_tree_keeps_odd_markers () {
  my @old = qw( Gone-Link-1.00 Link-Marker-1.00 Text-Marker-1.00 );
  my $dir = make_compressed_tree(@old);
  my ($gone, $link, $text) = map "$dir/$_/virtual_unzipped", @old;
  my $outside = tempdir(CLEANUP => 1);
  write_file("$outside/empty", "");
  my $gone_gz = "$dir/Gone-Link-1.00/gone.html.gz";
  symlink "$outside/gone.html.gz", $gone_gz or die "Can't symlink $gone_gz: $!";
  unlink $link or die "Can't unlink $link: $!";
  symlink "$outside/empty", $link or die "Can't symlink $link: $!";
  replace_page($text, "text\n");

  my ($out) = run_uncompress($dir);
  like $out, qr/converted 6 files in 3 directories/, "the run counts the pages";
  is readlink $link, "$outside/empty", "a marker that is a link stays a link";
  ok -e "$outside/empty", "the file outside remains";
  is slurp($text), "text\n", "a marker with text keeps its text";
  ok -z $gone, "the marker beside a broken link remains";

  my $status;
  ($out, $status) = run_uncompress($dir);
  isnt $status, 0, "a second uncompress fails with the broken link"
    or diag $out;
  ok warns($out, $gone_gz), "a second uncompress names the broken link";
}

sub uncompress_tree_converts_odd_names () {
  my $dir    = make_compressed_tree("Names-1.00");
  my $report = "$dir/Names-1.00";
  my @names  = (
    "a page.html", "new\nline.html", "-dash.html", "star*.html",
    "what?.html",  "[ab].html",
  );
  my $pages = { "empty.html" => "", map { $_ => "text of $_\n" } @names };
  write_gz("$report/$_", $pages->{$_}) for sort keys %$pages;

  my (undef, $out, $status) = dry_run_then_run($dir);
  is $status, 0, "uncompress succeeds with odd names" or diag $out;
  like $out, qr/converted 9 files in 1 directories/, "the run counts the pages";
  unlike $out, qr/\[WARNING\]/, "the output has no warning";
  is { map { $_ => slurp("$report/$_") } keys %$pages }, $pages,
    "every page holds its own text";
  my $empty = "$report/empty.html";
  ok -f $empty && !-l $empty && -z $empty,
    "the page of an empty gzip file is an empty regular file";
  is top_level_leftovers($report), [], "no gzip or temporary file remains";

  ($out, $status) = run_uncompress($dir);
  is $status, 0, "a second uncompress succeeds" or diag $out;
  like $out, qr/converted 0 files in 0 directories/,
    "a second uncompress converts nothing";
}

sub uncompress_tree_reports_unreadable_dirs () {
  skip_all "root can read any directory" unless $>;
  my @old    = qw( No-Access-1.00 No-Read-1.00 Readable-1.00 );
  my $dir    = make_compressed_tree(@old);
  my $mode   = { "No-Access-1.00" => 0000, "No-Read-1.00" => 0333 };
  my @closed = sort keys %$mode;
  my $before = { map { $_ => tree_state("$dir/$_") } @closed };

  chmod $mode->{$_}, "$dir/$_" or die "Can't chmod $dir/$_: $!" for @closed;
  my $runs = {};
  $runs->{"dry run"} = [run_uncompress($dir, "-d")];
  $runs->{run}       = [run_uncompress($dir)];
  chmod 0755, "$dir/$_" or die "Can't chmod $dir/$_: $!" for @closed;

  my $summary = {
    "dry run" => qr/would convert 2 files in 1 directories,/,
    run       => qr/\bconverted 2 files in 1 directories/,
  };
  for my $run (sort keys %$runs) {
    my ($out, $status) = $runs->{$run}->@*;
    isnt $status, 0, "the $run fails with unreadable directories" or diag $out;
    ok warns($out, "$dir/$_"), "the $run names $_" for @closed;
    like $out, qr/\[WARNING\].*could not read 2 directories/,
      "the $run counts the unreadable directories";
    like $out, $summary->{$run}, "the $run prints the summary";
    like $out, qr/\b0 directories had .* and 0 have no index page/,
      "the $run leaves the unreadable directories out of the index counts";
    for my $name (@closed) {
      is [grep /\Q$name/, index_lines($out)->@*], [],
        "the $run lists no index page of $name";
    }
  }
  for my $name (@closed) {
    my $report = "$dir/$name";
    is tree_state($report), $before->{$name},
      "the runs change nothing in $name";
    for my $page (qw( index.html lib-One-pm.html )) {
      ok -e "$report/$page.gz", "$name/$page.gz remains";
      ok -z "$report/$page",    "$name/$page stays empty";
    }
    ok -e "$report/virtual_unzipped", "$name keeps the marker";
  }
  is slurp("$dir/Readable-1.00/$_"), "Readable-1.00/$_\n",
    "Readable-1.00/$_ holds its text"
    for @Report_files;
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

sub make_latest_stub ($bin, @latest) {
  my $print = join "", map "echo $_; ", @latest;
  write_file("$bin/perl", <<~SH);
    #!/bin/sh
    case " \$* " in
      *" --latest "*) ${print}exit ;;
    esac
    echo "\$*" >>"\$STUB_CALLS"
    case "\$*" in
      *bin/cpancover*) sed 's/^/< /' >>"\$STUB_CALLS" ;;
    esac
    echo 1
    SH
  chmod 0755, "$bin/perl" or die "Can't chmod perl stub: $!";
}

sub rebuild_module_resolves_name () {
  my $latest = "P/PJ/PJCJ/Perl-Critic-PJCJ-v9.9.9.tar.gz";
  my $bin    = tempdir(CLEANUP => 1);
  my $work   = tempdir(CLEANUP => 1);
  make_build_stubs($bin);
  make_latest_stub($bin, $latest);
  my $marker = "$work/results/__rebuilt__/Perl-Critic-PJCJ-v9.9.9";
  for my $d ("$work/results", "$work/results/__rebuilt__") {
    mkdir $d or die "Can't mkdir $d: $!";
  }
  write_file($marker, "1\n");
  local $ENV{PATH}       = "$bin:$ENV{PATH}";
  local $ENV{STUB_CALLS} = "$work/calls";

  my $rebuild = "cpancover-rebuild-module Perl-Critic-PJCJ </dev/null";
  my ($out, $exit) = dc_in($work, "-r", "$work/results", $rebuild);
  is $exit, 0, "rebuild of a distribution name succeeds" or diag $out;
  ok !-e $marker, "the marker of the current release is removed";
  my ($stdin) = slurp("$work/calls") =~ /--build [^\n]*\n((?:< [^\n]*\n)*)/;
  is $stdin, "< $latest\n", "the build reads only the current release";
}

sub rebuild_module_needs_one_release () {
  my @paths = map "P/PJ/PJCJ/Perl-Critic-PJCJ-v$_.tar.gz", qw( 9.9.8 9.9.9 );
  for my $latest ([], \@paths) {
    my $bin  = tempdir(CLEANUP => 1);
    my $work = tempdir(CLEANUP => 1);
    make_build_stubs($bin);
    make_latest_stub($bin, @$latest);
    local $ENV{PATH}       = "$bin:$ENV{PATH}";
    local $ENV{STUB_CALLS} = "$work/calls";

    my $n       = @$latest;
    my $rebuild = "cpancover-rebuild-module Perl-Critic-PJCJ </dev/null";
    my ($out, $exit) = dc_in($work, "-r", "$work/results", $rebuild);

    isnt $exit, 0, "rebuild fails with $n releases";
    like $out, qr/Can't find the current release of Perl-Critic-PJCJ/,
      "the failure names the distribution";
    my $calls = -e "$work/calls" ? slurp("$work/calls") : "";
    unlike $calls, qr/--build/, "no build runs";
  }
}

sub render_module_reads_input () {
  my $home = tempdir(CLEANUP => 1);
  mkdir "$home/input" or die "Can't mkdir $home/input: $!";
  write_file("$home/input/cover.json", "{}\n");
  my $call = cpancover_call(["cpancover-render-module"], HOME => $home);
  like $call, qr| --render \Q$home\E/input \Q$home\E/output$|,
    "the render reads the input";
  is slurp("$home/input/cover.json"), "{}\n", "the input is unchanged";
  ok !-e "$home/work",  "no copy of the input is made";
  ok -d "$home/output", "the output dir is created";
}

sub main () {
  my @tests = qw(
    compress_recipe
    uncompress_recipe
    uncompress_tree_recipe
    uncompress_tree_leaves_bad_pages
    uncompress_tree_leaves_linked_pages
    uncompress_tree_leaves_read_only_dir
    uncompress_tree_empty_and_equal_pages
    uncompress_tree_index_pages
    uncompress_tree_dry_run
    uncompress_tree_odd_pages
    uncompress_tree_leaves_marker_page
    uncompress_tree_leaves_double_suffixes
    uncompress_tree_leaves_gz_links
    uncompress_tree_keeps_odd_markers
    uncompress_tree_converts_odd_names
    uncompress_tree_reports_unreadable_dirs
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
    render_module_reads_input
    rebuild_module_resolves_name
    rebuild_module_needs_one_release
  );
  for my $test (@tests) {
    no strict qw( refs );
    subtest $test => \&$test;
  }
  done_testing;
}

main;

#!/usr/bin/perl
# HARNESS-DURATION-LONG

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.42.0;

use Test2::V0     qw( done_testing is like ok skip_all subtest unlike );
use File::Temp    qw( tempdir );
use JSON::MaybeXS ();

use Devel::Cover::Collection ();

# _sys() uses Time::HiRes::alarm() which is not available on Windows
my $Is_win32 = $^O eq "MSWin32";

sub constructor_defaults () {
  my $c = Devel::Cover::Collection->new;
  is $c->build_dirs,    [],           "build_dirs defaults to empty arrayref";
  is $c->modules,       [],           "modules defaults to empty arrayref";
  is $c->docker,        "docker",     "docker defaults to 'docker'";
  is $c->dryrun,        0,            "dryrun defaults to 0";
  is $c->env,           "prod",       "env defaults to 'prod'";
  is $c->force,         0,            "force defaults to 0";
  is $c->local,         0,            "local defaults to 0";
  is $c->output_file,   "index.html", "output_file defaults to 'index.html'";
  is $c->rebuild,       0,            "rebuild defaults to 0";
  is $c->rebuild_batch, 100,          "rebuild_batch defaults to 100";
  is $c->report,        "html",       "report defaults to 'html'";
  is $c->timeout,       30 * 60,      "timeout defaults to 1800 (30 minutes)";
  is $c->verbose,       0,            "verbose defaults to 0";
  is $c->workers,       0,            "workers defaults to 0";
  is ref($c->cpan_dir), "ARRAY",      "cpan_dir is an arrayref";
  is $c->bin_dir,       undef,        "bin_dir is undef by default";
  is $c->results_dir,   undef,        "results_dir is undef by default";
  is $c->module_file,   undef,        "module_file is undef by default";
  is $c->dir,           undef,        "dir is undef by default";
  is $c->file,          undef,        "file is undef by default";
}

sub constructor_with_args () {
  my $c = Devel::Cover::Collection->new(
    bin_dir       => "/usr/bin",
    results_dir   => "/tmp/results",
    docker        => "podman",
    dryrun        => 1,
    env           => "dev",
    force         => 1,
    local         => 1,
    output_file   => "report.html",
    rebuild       => 1,
    rebuild_batch => 25,
    report        => "html_minimal",
    timeout       => 600,
    verbose       => 1,
    workers       => 4,
  );
  is $c->bin_dir,     "/usr/bin",     "bin_dir set via constructor";
  is $c->results_dir, "/tmp/results", "results_dir set via constructor";
  is $c->docker,      "podman",       "docker overridden via constructor";
  is $c->dryrun,      1,              "dryrun overridden via constructor";
  is $c->env,         "dev",          "env overridden via constructor";
  is $c->force,       1,              "force overridden via constructor";
  is $c->local,       1,              "local overridden via constructor";
  is $c->output_file, "report.html",  "output_file overridden via constructor";
  is $c->rebuild,     1,              "rebuild overridden via constructor";
  is $c->rebuild_batch, 25,             "rebuild_batch overridden";
  is $c->report,        "html_minimal", "report overridden via constructor";
  is $c->timeout,       600,            "timeout overridden via constructor";
  is $c->verbose,       1,              "verbose overridden via constructor";
  is $c->workers,       4,              "workers overridden via constructor";
}

sub ro_accessors () {
  my $c = Devel::Cover::Collection->new(bin_dir => "/usr/bin", verbose => 1);
  is $c->bin_dir, "/usr/bin", "ro accessor bin_dir readable";
  is $c->verbose, 1,          "ro accessor verbose readable";
  ok !$c->can("set_bin_dir"), "ro accessor bin_dir has no setter";
  ok !$c->can("set_verbose"), "ro accessor verbose has no setter";
}

sub rw_accessors () {
  my $c = Devel::Cover::Collection->new;
  is $c->dir,  undef, "rw accessor dir initially undef";
  is $c->file, undef, "rw accessor file initially undef";
  $c->dir("/tmp/test");
  is $c->dir, "/tmp/test", "rw accessor dir writable";
  $c->file("/tmp/test.html");
  is $c->file, "/tmp/test.html", "rw accessor file writable";
}

sub rwp_accessors () {
  my $c = Devel::Cover::Collection->new;
  is $c->build_dirs, [], "rwp accessor build_dirs readable";
  ok $c->can("_set_build_dirs"), "rwp accessor build_dirs has _set_build_dirs";
  $c->_set_build_dirs(["/dir1", "/dir2"]);
  is $c->build_dirs, ["/dir1", "/dir2"],
    "rwp accessor build_dirs settable via _set_build_dirs";
  is $c->modules, [], "rwp accessor modules readable";
  ok $c->can("_set_modules"), "rwp accessor modules has _set_modules";
  $c->_set_modules(["Foo::Bar"]);
  is $c->modules, ["Foo::Bar"],
    "rwp accessor modules settable via _set_modules";
  is $c->module_file, undef, "rwp accessor module_file readable";
  ok $c->can("_set_module_file"),
    "rwp accessor module_file has _set_module_file";
  $c->_set_module_file("/tmp/modules.txt");
  is $c->module_file, "/tmp/modules.txt",
    "rwp accessor module_file settable via _set_module_file";
}

sub add_modules () {
  my $c = Devel::Cover::Collection->new;
  is $c->modules, [], "modules starts empty";
  $c->add_modules("Foo::Bar");
  is $c->modules, ["Foo::Bar"], "add_modules adds single module";
  $c->add_modules("Baz::Qux", "Quux::Corge");
  is $c->modules, ["Foo::Bar", "Baz::Qux", "Quux::Corge"],
    "add_modules adds multiple modules";
}

sub set_modules () {
  my $c = Devel::Cover::Collection->new;
  $c->add_modules("Foo::Bar", "Baz::Qux");
  is $c->modules, ["Foo::Bar", "Baz::Qux"], "modules populated";
  $c->set_modules("New::Module");
  is $c->modules, ["New::Module"], "set_modules replaces all modules";
  $c->set_modules("A", "B", "C");
  is $c->modules, ["A", "B", "C"], "set_modules with multiple modules";
}

sub set_module_file () {
  my $c = Devel::Cover::Collection->new;
  is $c->module_file, undef, "module_file initially undef";
  $c->set_module_file("/tmp/modules.txt");
  is $c->module_file, "/tmp/modules.txt", "set_module_file sets value";
  $c->set_module_file("/other/path.txt");
  is $c->module_file, "/other/path.txt", "set_module_file updates value";
}

sub process_module_file () {
  my $dir  = tempdir(CLEANUP => 1);
  my $file = "$dir/modules.txt";
  open my $fh, ">", $file or die "Can't write $file: $!";
  print $fh <<~TEXT;
    # Comment line
    Foo::Bar
      # Indented comment
    Baz::Qux

    # Empty lines above
    Quux::Corge
    TEXT
  close $fh or die "Can't close $file: $!";

  my $c = Devel::Cover::Collection->new(module_file => $file);
  $c->process_module_file;
  is $c->modules, ["Foo::Bar", "Baz::Qux", "Quux::Corge"],
    "process_module_file filters comments and blank lines";

  my $c2 = Devel::Cover::Collection->new;
  $c2->process_module_file;
  is $c2->modules, [], "process_module_file with undef module_file";

  my $c3 = Devel::Cover::Collection->new(module_file => "");
  $c3->process_module_file;
  is $c3->modules, [], "process_module_file with empty module_file";

  my $c4 = Devel::Cover::Collection->new(module_file => $file);
  $c4->add_modules("Existing::Module");
  $c4->process_module_file;
  is $c4->modules, ["Existing::Module", "Foo::Bar", "Baz::Qux", "Quux::Corge"],
    "process_module_file appends to existing modules";
}

sub made_res_dir () {
  skip_all "uses fsys which requires alarm (not available on Windows)"
    if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);
  my $c   = Devel::Cover::Collection->new(results_dir => $dir);

  my ($path, $output) = $c->made_res_dir;
  is $path, $dir, "made_res_dir returns results_dir path";
  ok -d $path, "made_res_dir creates directory";

  my ($sub_path, $sub_output) = $c->made_res_dir("subdir");
  is $sub_path, "$dir/subdir", "made_res_dir with subdir returns correct path";
  ok -d $sub_path, "made_res_dir creates subdirectory";

  my ($nested_path) = $c->made_res_dir("a/b/c");
  is $nested_path, "$dir/a/b/c", "made_res_dir handles nested path";
  ok -d $nested_path, "made_res_dir creates nested directories";

  my $c2 = Devel::Cover::Collection->new;
  eval { $c2->made_res_dir };
  like $@, qr/No results dir/, "made_res_dir dies without results_dir";

  # rebuild_pass triggers hundreds of failed_dir/rebuilt_dir calls per
  # batch; each was forking mkdir -p. After the first creation the
  # method should be a no-op so repeated calls don't refork.
  my $cdir = tempdir(CLEANUP => 1);
  my $cc   = Devel::Cover::Collection->new(results_dir => $cdir);
  $cc->made_res_dir("cached");
  rmdir "$cdir/cached" or die "Can't rmdir: $!";
  my ($cpath) = $cc->made_res_dir("cached");
  is $cpath, "$cdir/cached", "cached made_res_dir returns the same path";
  ok !-d $cpath, "cached made_res_dir does not refork mkdir";
}

sub path_methods () {
  skip_all
    "failed_dir uses fsys which requires alarm (not available on Windows)"
    if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);
  my $c   = Devel::Cover::Collection->new(results_dir => $dir);

  is $c->covered_dir("Foo-Bar"), "$dir/Foo-Bar",
    "covered_dir returns results_dir/module";

  my $failed = $c->failed_dir;
  is $failed, "$dir/__failed__", "failed_dir returns __failed__ path";
  ok -d $failed, "failed_dir creates the directory";

  is $c->failed_file("Foo-Bar"), "$dir/__failed__/Foo-Bar",
    "failed_file returns path in __failed__ dir";
}

sub status_tracking () {
  skip_all
    "set_failed uses fsys which requires alarm (not available on Windows)"
    if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);
  my $c   = Devel::Cover::Collection->new(results_dir => $dir);

  ok !$c->is_covered("Foo-Bar"), "is_covered false when dir doesn't exist";
  ok !$c->is_failed("Foo-Bar"),  "is_failed false when file doesn't exist";

  mkdir "$dir/Foo-Bar" or die "Can't mkdir: $!";
  ok $c->is_covered("Foo-Bar"), "is_covered true when dir exists";
  ok !$c->is_failed("Foo-Bar"), "is_failed still false";

  $c->set_failed("Baz-Qux");
  ok !$c->is_covered("Baz-Qux"), "is_covered false for failed module";
  ok $c->is_failed("Baz-Qux"),   "is_failed true after set_failed";

  my $ff = $c->failed_file("Baz-Qux");
  ok -e $ff, "set_failed creates file";
  open my $fh, "<", $ff or die "Can't read $ff: $!";
  my $content = do { local $/; <$fh> };
  close $fh or die "Can't close $ff: $!";
  like $content, qr/\w{3} \w{3} +\d+ \d+:\d+:\d+ \d{4}/,
    "set_failed writes timestamp";

  $c->set_failed("Quux-Corge");
  ok $c->is_failed("Quux-Corge"), "is_failed true before set_covered";
  $c->set_covered("Quux-Corge");
  ok !$c->is_failed("Quux-Corge"),      "is_failed false after set_covered";
  ok !-e $c->failed_file("Quux-Corge"), "set_covered removes failed file";

  $c->set_covered("Never-Failed");
  ok !$c->is_failed("Never-Failed"), "set_covered on non-existent is safe";
}

sub sys_successful_command () {
  skip_all "alarm not available on Windows" if $Is_win32;
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $output = $c->sys("true");
  is $output, "", "sys returns empty string for short successful command";
}

sub sys_failed_command () {
  skip_all "alarm not available on Windows" if $Is_win32;
  my $c       = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $warning = "";
  local $SIG{__WARN__} = sub { $warning .= shift };
  my $output = $c->sys("false");
  is $output, "", "sys returns empty string on failed command";
  like $warning, qr/Error running false/, "sys warns on failed command";
}

sub bsys_successful_command () {
  skip_all "alarm not available on Windows" if $Is_win32;
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $output = $c->bsys("echo", "buffered output");
  like $output, qr/buffered output/, "bsys captures output";
}

sub bsys_failed_command () {
  skip_all "alarm not available on Windows" if $Is_win32;
  my $c       = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $warning = "";
  local $SIG{__WARN__} = sub { $warning .= shift };
  my $output = $c->bsys("false");
  is $output, "", "bsys returns empty string on failed command";
  like $warning, qr/Error running false/, "bsys warns on failed command";
}

sub fsys_successful_command () {
  skip_all "alarm not available on Windows" if $Is_win32;
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $output = $c->fsys("true");
  is $output, "", "fsys returns empty string for short successful command";
}

sub fsys_failed_command () {
  skip_all "alarm not available on Windows" if $Is_win32;
  my $c       = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $warning = "";
  local $SIG{__WARN__} = sub { $warning .= shift };
  my $died = 0;
  eval {
    $c->fsys("false");
    1;
  } or $died = 1;
  ok $died, "fsys dies on failed command";
  like $warning, qr/Error running false/, "fsys warns on failed command";
}

sub fbsys_successful_command () {
  skip_all "alarm not available on Windows" if $Is_win32;
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $output = $c->fbsys("echo", "fatal buffered");
  like $output, qr/fatal buffered/, "fbsys captures output";
}

sub fbsys_failed_command () {
  skip_all "alarm not available on Windows" if $Is_win32;
  my $c       = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $warning = "";
  local $SIG{__WARN__} = sub { $warning .= shift };
  my $died = 0;
  eval {
    $c->fbsys("false");
    1;
  } or $died = 1;
  ok $died, "fbsys dies on failed command";
  like $warning, qr/Error running false/, "fbsys warns on failed command";
}

sub sys_timeout () {
  skip_all "alarm not available on Windows" if $Is_win32;
  my $c       = Devel::Cover::Collection->new(verbose => 0, timeout => 1);
  my $warning = "";
  local $SIG{__WARN__} = sub { $warning .= shift };
  my $output = $c->sys("sleep", "10");
  is $output, "", "sys returns empty string on timeout";
  like $warning, qr/Timed out after 1 seconds/, "sys warns on timeout";
  like $warning, qr/killed \d+ processes/, "sys warns about killed processes";
}

sub sys_verbose_output () {
  skip_all "alarm not available on Windows" if $Is_win32;
  my $c      = Devel::Cover::Collection->new(verbose => 1, timeout => 10);
  my $output = $c->bsys("printf", "result\\n");
  unlike $output, qr/dc -> /, "verbose mode does not prefix captured output";
  is $output, "result\n", "captured output is only the command's stdout";
}

sub bsys_multiline_output () {
  skip_all "alarm not available on Windows" if $Is_win32;
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $output = $c->bsys("printf", "line1\\nline2\\nline3\\n");
  like $output, qr/line1/, "bsys captures first line";
  like $output, qr/line2/, "bsys captures middle line";
  like $output, qr/line3/, "bsys captures last line";
}

sub bsys_stderr_capture () {
  skip_all "alarm not available on Windows" if $Is_win32;
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $output = $c->bsys("sh", "-c", "echo stderr >&2");
  like $output, qr/stderr/, "bsys captures stderr (redirected to stdout)";
}

sub dc_file () {
  my $c1 = Devel::Cover::Collection->new(local => 0);
  is $c1->dc_file, "utils/dc", "dc_file returns utils/dc when not local";

  my $c2 = Devel::Cover::Collection->new(local => 1);
  if (-d "/dc") {
    is $c2->dc_file, "/dc/utils/dc", "dc_file returns /dc/utils/dc when local";
  } else {
    is $c2->dc_file, "utils/dc",
      "dc_file returns utils/dc when local but /dc missing";
  }
}

sub coverage_class_method () {
  my $c = Devel::Cover::Collection->new;
  is $c->coverage_class("n/a"), "na", "coverage_class('n/a') -> 'na'";
  is $c->coverage_class(0),     "c0", "coverage_class(0) -> 'c0'";
  is $c->coverage_class(50),    "c0", "coverage_class(50) -> 'c0'";
  is $c->coverage_class(74.99), "c0", "coverage_class(74.99) -> 'c0'";
  is $c->coverage_class(75),    "c1", "coverage_class(75) -> 'c1'";
  is $c->coverage_class(89.99), "c1", "coverage_class(89.99) -> 'c1'";
  is $c->coverage_class(90),    "c2", "coverage_class(90) -> 'c2'";
  is $c->coverage_class(99.99), "c2", "coverage_class(99.99) -> 'c2'";
  is $c->coverage_class(100),   "c3", "coverage_class(100) -> 'c3'";
}

sub write_json () {
  skip_all "alarm not available on Windows" if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);
  my $c   = Devel::Cover::Collection->new(results_dir => $dir);

  my $vars = {
    vals => {
      "Foo-Bar-1.23" => {
        module =>
          { module => "Foo-Bar-1.23", name => "Foo-Bar", version => "1.23" },
        statement  => { pc => "85.00" },
        branch     => { pc => "70.00" },
        condition  => { pc => "n/a" },
        subroutine => { pc => "100.00" },
        total      => { pc => "82.50" },
        link       => "/Foo-Bar/index.html",
        log        => "build.log",
      },
    },
  };

  $c->write_json($vars);

  my $json_file = "$dir/cpancover.json";
  ok -e $json_file, "write_json creates cpancover.json";

  open my $fh, "<", $json_file or die "Can't read $json_file: $!";
  my $content = do { local $/; <$fh> };
  close $fh or die "Can't close $json_file: $!";

  like $content,   qr/"Foo-Bar"/,   "JSON contains module name";
  like $content,   qr/"1\.23"/,     "JSON contains version";
  like $content,   qr/"statement"/, "JSON contains statement coverage";
  like $content,   qr/"85\.00"/,    "JSON contains coverage percentage";
  unlike $content, qr/"condition"/, "JSON excludes n/a criteria";
  unlike $content, qr/"link"/,      "JSON excludes link field";
  unlike $content, qr/"log"/,       "JSON excludes log field";
}

sub compress_old_versions () {
  skip_all "uses fsys which requires alarm (not available on Windows)"
    if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);

  # Reproduce GH-409: CPAN versions that sort incorrectly when numified.
  # 0.41 numifies to 0.410, less than 0.700/0.800/0.900, so the latest
  # release was compressed and removed under the old version-based sort.
  my @versions = (
    { ver => "0.7",  start => 1000 },
    { ver => "0.8",  start => 2000 },
    { ver => "0.9",  start => 3000 },
    { ver => "0.41", start => 4000 },
  );

  my $json = JSON::MaybeXS->new(utf8 => 1);
  for my $v (@versions) {
    my $mod_dir = "$dir/Net-RDAP-$v->{ver}";
    mkdir $mod_dir or die "Can't mkdir $mod_dir: $!";
    my $cover = { runs =>
      [{ name => "Net-RDAP", version => $v->{ver}, start => $v->{start} }] };
    open my $fh, ">", "$mod_dir/cover.json" or die "Can't write: $!";
    print $fh $json->encode($cover);
    close $fh or die "Can't close: $!";
  }

  my $c = Devel::Cover::Collection->new(results_dir => $dir, dryrun => 1);

  my $outfile = "$dir/compress_output.txt";
  {
    open my $saved, ">&", STDOUT   or die "Can't dup STDOUT: $!";
    open STDOUT,    ">",  $outfile or die "Can't redirect STDOUT: $!";
    $c->compress_old_versions(3);
    open STDOUT, ">&", $saved or die "Can't restore STDOUT: $!";
  }
  open my $ofh, "<", $outfile or die "Can't read $outfile: $!";
  my $output = do { local $/; <$ofh> };
  close $ofh or die "Can't close $outfile: $!";

  # 4 versions, keep 3: the oldest by start time should be compressed
  like $output, qr/^compressing Net-RDAP-0\.7$/m,
    "oldest version by start time is compressed";
  unlike $output, qr/^compressing Net-RDAP-0\.41$/m,
    "latest release is kept (was removed by numeric version sort)";
  unlike $output, qr/^compressing Net-RDAP-0\.9$/m,
    "recent version 0.9 is kept";
  unlike $output, qr/^compressing Net-RDAP-0\.8$/m,
    "recent version 0.8 is kept";
}

sub filter_build_dirs_to_targets () {
  my $c = Devel::Cover::Collection->new(modules => [
    "P/PJ/PJCJ/Perl-Critic-PJCJ-v0.2.4.tar.gz",
    "A/AU/AUTHOR/My-Module-1.23.tar.gz",
  ]);
  $c->_set_build_dirs([
    "/home/x/.cpan/build/Perl-Critic-PJCJ-v0.2.4-0",
    "/home/x/.cpan/build/My-Module-1.23-3",
    "/home/x/.cpan/build/PPI-1.280-0",
    "/home/x/.cpan/build/Test-Deep-1.204-1",
  ]);
  $c->filter_build_dirs_to_targets;
  is $c->build_dirs, [
      "/home/x/.cpan/build/Perl-Critic-PJCJ-v0.2.4-0",
      "/home/x/.cpan/build/My-Module-1.23-3",
    ],
    "filter keeps only build dirs that match a target distdir";

  my $c2
    = Devel::Cover::Collection->new(modules => ["T/TA/TAR/Target-1.0.tar.gz"]);
  $c2->_set_build_dirs([
    "/cpan/build/Target-1.0-0", "/cpan/build/Target-1.0-1",
    "/cpan/build/Target-1.0-2",
  ]);
  $c2->filter_build_dirs_to_targets;
  is $c2->build_dirs, [
      "/cpan/build/Target-1.0-0", "/cpan/build/Target-1.0-1",
      "/cpan/build/Target-1.0-2",
    ],
    "filter keeps all reinstall attempts of the same target";

  my $c3 = Devel::Cover::Collection->new;
  $c3->_set_build_dirs(["/cpan/build/Random-1.0-0"]);
  $c3->filter_build_dirs_to_targets;
  is $c3->build_dirs, [], "filter empties build_dirs when modules is empty";

  my $c4
    = Devel::Cover::Collection->new(modules => ["A/AU/AUTHOR/Foo-1.0.tar.gz"]);
  $c4->_set_build_dirs([]);
  $c4->filter_build_dirs_to_targets;
  is $c4->build_dirs, [], "filter is a no-op on empty build_dirs";
}

sub rebuilt_markers () {
  skip_all
    "rebuilt_dir uses fsys which requires alarm (not available on Windows)"
    if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);
  my $c   = Devel::Cover::Collection->new(results_dir => $dir);

  is $c->rebuilt_dir, "$dir/__rebuilt__", "rebuilt_dir path";
  ok -d $c->rebuilt_dir, "rebuilt_dir creates directory";
  is $c->rebuilt_file("Foo-1.0"), "$dir/__rebuilt__/Foo-1.0",
    "rebuilt_file returns path in __rebuilt__ dir";

  ok !$c->is_rebuilt("Foo-1.0"), "is_rebuilt false when no marker";
  $c->set_rebuilt("Foo-1.0");
  ok $c->is_rebuilt("Foo-1.0"),      "is_rebuilt true after set_rebuilt";
  ok -e $c->rebuilt_file("Foo-1.0"), "set_rebuilt writes marker file";

  open my $fh, "<", $c->rebuilt_file("Foo-1.0") or die "Can't read marker: $!";
  my $content = do { local $/; <$fh> };
  close $fh or die "Can't close marker: $!";
  like $content, qr/\w{3} \w{3} +\d+ \d+:\d+:\d+ \d{4}/,
    "set_rebuilt writes timestamp";
}

sub unflag_all_rebuilt_method () {
  skip_all "unflag_all_rebuilt uses fsys which requires alarm" if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);
  my $c   = Devel::Cover::Collection->new(results_dir => $dir);

  $c->set_rebuilt("A-1.0");
  $c->set_rebuilt("B-2.0");
  ok $c->is_rebuilt("A-1.0"), "A-1.0 flagged before unflag";
  ok $c->is_rebuilt("B-2.0"), "B-2.0 flagged before unflag";

  $c->unflag_all_rebuilt;
  ok !-d "$dir/__rebuilt__",   "unflag_all_rebuilt removes the directory";
  ok !$c->is_rebuilt("A-1.0"), "is_rebuilt false after unflag";
  ok !$c->is_rebuilt("B-2.0"), "is_rebuilt false after unflag";

  # made_res_dir caches successful creations; unflag must invalidate
  # its entry so a subsequent set_rebuilt recreates __rebuilt__/.
  $c->set_rebuilt("C-3.0");
  ok -d "$dir/__rebuilt__",   "rebuilt dir recreated on next set_rebuilt";
  ok $c->is_rebuilt("C-3.0"), "set_rebuilt works after unflag";
}

sub known_distdirs_method () {
  skip_all "uses fsys which requires alarm" if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);
  my $c   = Devel::Cover::Collection->new(results_dir => $dir);

  mkdir "$dir/Alpha-1.0" or die "Can't mkdir: $!";
  open my $fh1, ">", "$dir/Alpha-1.0/cover.json" or die;
  print $fh1 "{}";
  close $fh1 or die;

  mkdir "$dir/NoCover-1.0" or die "Can't mkdir: $!";

  $c->set_failed("Bravo-2.0");

  mkdir "$dir/Charlie-3.0" or die "Can't mkdir: $!";
  open my $fh2, ">", "$dir/Charlie-3.0/cover.json" or die;
  print $fh2 "{}";
  close $fh2 or die;
  $c->set_failed("Charlie-3.0");

  my @d = $c->known_distdirs;
  is \@d, ["Alpha-1.0", "Bravo-2.0", "Charlie-3.0"],
    "known_distdirs: cover.json dirs + __failed__ markers, deduped, sorted";
}

sub all_rebuilt_method () {
  skip_all "uses fsys which requires alarm" if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);
  my $c   = Devel::Cover::Collection->new(results_dir => $dir);

  ok $c->all_rebuilt, "all_rebuilt true when no distdirs known";

  mkdir "$dir/Alpha-1.0" or die "Can't mkdir: $!";
  open my $fh, ">", "$dir/Alpha-1.0/cover.json" or die;
  print $fh "{}";
  close $fh or die;
  $c->set_failed("Bravo-2.0");

  ok !$c->all_rebuilt, "all_rebuilt false with no flags";
  $c->set_rebuilt("Alpha-1.0");
  ok !$c->all_rebuilt, "all_rebuilt false with partial flags";
  $c->set_rebuilt("Bravo-2.0");
  ok $c->all_rebuilt, "all_rebuilt true when every entry flagged";
}

sub make_cpanm_stub ($bin) {
  open my $fh, ">", "$bin/cpanm" or die "Can't write cpanm stub: $!";
  print $fh qq(#!/bin/sh\necho "AUTHOR/\$2-1.0.tar.gz"\n);
  close $fh or die "Can't close cpanm stub: $!";
  chmod 0755, "$bin/cpanm" or die "Can't chmod cpanm stub: $!";
}

sub touch_empty_file ($path) {
  open my $fh, ">", $path or die "Can't touch $path: $!";
  close $fh or die "Can't close $path: $!";
}

sub write_log_ref ($distdir_path, $contents) {
  mkdir $distdir_path or die "Can't mkdir $distdir_path: $!";
  open my $fh, ">", "$distdir_path/.log_ref" or die "Can't write .log_ref: $!";
  print $fh $contents;
  close $fh or die "Can't close .log_ref: $!";
}

sub next_rebuild_batch_method () {
  skip_all "uses fsys which requires alarm" if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);
  my $bin = tempdir(CLEANUP => 1);
  make_cpanm_stub($bin);
  local $ENV{PATH} = "$bin:$ENV{PATH}";

  my $c
    = Devel::Cover::Collection->new(results_dir => $dir, rebuild_batch => 2);

  for my $spec (
    ["Alpha-1.0",   100],
    ["Bravo-2.0",   200],
    ["Charlie-3.0", 300],
    ["Delta-4.0",   400],
  ) {
    my ($d, $mtime) = @$spec;
    mkdir "$dir/$d" or die "Can't mkdir: $!";
    my $cover = "$dir/$d/cover.json";
    open my $fh, ">", $cover or die "Can't write: $!";
    print $fh "{}";
    close $fh or die;
    utime $mtime, $mtime, $cover or die "Can't utime: $!";
  }

  is [$c->next_rebuild_batch], ["Alpha-1.0", "Bravo-2.0"],
    "next_rebuild_batch returns oldest first, limited to rebuild_batch";

  $c->set_rebuilt("Alpha-1.0");
  is [$c->next_rebuild_batch], ["Bravo-2.0", "Charlie-3.0"],
    "next_rebuild_batch excludes already-rebuilt entries";

  $c->set_rebuilt($_) for qw( Bravo-2.0 Charlie-3.0 Delta-4.0 );
  is [$c->next_rebuild_batch], [],
    "next_rebuild_batch returns empty when all rebuilt";

  my $c0
    = Devel::Cover::Collection->new(results_dir => $dir, rebuild_batch => 0);
  is [$c0->next_rebuild_batch], [],
    "next_rebuild_batch returns empty when rebuild_batch is 0";

  my $dir2 = tempdir(CLEANUP => 1);
  my $c2
    = Devel::Cover::Collection->new(results_dir => $dir2, rebuild_batch => 10);
  $c2->set_failed("Foo-1.0");
  utime 50, 50, $c2->failed_file("Foo-1.0") or die "utime: $!";
  mkdir "$dir2/Bar-2.0" or die;
  open my $fh, ">", "$dir2/Bar-2.0/cover.json" or die;
  print $fh "{}";
  close $fh or die;
  utime 1000, 1000, "$dir2/Bar-2.0/cover.json" or die;

  is [$c2->next_rebuild_batch], ["Foo-1.0", "Bar-2.0"],
    "next_rebuild_batch falls back to __failed__ mtime when no cover.json";
}

sub status_tracking_rebuild_mode () {
  skip_all "uses fsys which requires alarm" if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);
  my $c   = Devel::Cover::Collection->new(results_dir => $dir, rebuild => 1);

  mkdir "$dir/Foo-1.0" or die "Can't mkdir: $!";
  ok !$c->is_covered("Foo-1.0"),
    "is_covered false in rebuild mode when dir exists but not rebuilt";
  $c->set_rebuilt("Foo-1.0");
  ok $c->is_covered("Foo-1.0"),
    "is_covered true in rebuild mode when dir exists and rebuilt";

  $c->set_failed("Bar-2.0");
  ok !$c->is_failed("Bar-2.0"),
    "is_failed false in rebuild mode when marker exists but not rebuilt";
  $c->set_rebuilt("Bar-2.0");
  ok $c->is_failed("Bar-2.0"),
    "is_failed true in rebuild mode when marker exists and rebuilt";

  my $c2 = Devel::Cover::Collection->new(results_dir => $dir, rebuild => 0);
  ok $c2->is_covered("Foo-1.0"),
    "is_covered ignores rebuilt flag when not in rebuild mode";
  ok $c2->is_failed("Bar-2.0"),
    "is_failed ignores rebuilt flag when not in rebuild mode";
}

sub cpan_path_for_method () {
  skip_all "uses fsys which requires alarm" if $Is_win32;

  # Mimic real cpanm: it only accepts module names (Foo::Bar), not
  # distribution names (Foo-Bar). Reject distribution form so we catch
  # regressions where the caller forgets to translate dashes to colons.
  my $bin = tempdir(CLEANUP => 1);
  open my $fh, ">", "$bin/cpanm" or die "Can't write stub: $!";
  print $fh <<~'BASH';
    #!/bin/sh
    case "$2" in
      *::*)
        mod=$2
        dist=${mod//::/-}
        echo "AUTHOR/${dist}-9.99.tar.gz"
        ;;
      *) exit 1 ;;
    esac
    BASH
  close $fh or die;
  chmod 0755, "$bin/cpanm" or die;
  local $ENV{PATH} = "$bin:$ENV{PATH}";

  # Prefer .log_ref when present.
  my $dir = tempdir(CLEANUP => 1);
  mkdir "$dir/Foo-Bar-1.23" or die;
  open my $lref, ">", "$dir/Foo-Bar-1.23/.log_ref" or die;
  print $lref "A-AU-AUTHOR-Foo-Bar-1.23.tar.gz--1234567890.123.out.gz\n";
  close $lref or die;
  my $c = Devel::Cover::Collection->new(results_dir => $dir);
  is $c->cpan_path_for("Foo-Bar-1.23"), "A/AU/AUTHOR/Foo-Bar-1.23.tar.gz",
    "cpan_path_for prefers .log_ref when available";

  # Fall back to top-level log filename for failed entries (no distdir).
  open my $log, ">", "$dir/Q-QU-QUX-Only-Log-2.00.tar.gz--111.222.out.gz"
    or die;
  close $log or die;
  is $c->cpan_path_for("Only-Log-2.00"), "Q/QU/QUX/Only-Log-2.00.tar.gz",
    "cpan_path_for parses top-level log filename when no .log_ref";

  # Multiple top-level logs for the same distdir: pick the newest by
  # mtime so repeated runs settle on the most recent coverage. Use a
  # fresh results_dir so the log index cache starts empty and sees both
  # files.
  my $mdir = tempdir(CLEANUP => 1);
  my $old  = "$mdir/A-AU-OLDAUTH-Multi-1.0.tar.gz--111.out.gz";
  my $new  = "$mdir/A-AU-NEWAUTH-Multi-1.0.tar.gz--222.out.gz";
  touch_empty_file($old);
  touch_empty_file($new);
  my $now = time;
  utime $now - 100, $now - 100, $old or die "utime $old: $!";
  utime $now,       $now,       $new or die "utime $new: $!";
  my $cm = Devel::Cover::Collection->new(results_dir => $mdir);
  is $cm->cpan_path_for("Multi-1.0"), "A/AU/NEWAUTH/Multi-1.0.tar.gz",
    "cpan_path_for picks newest log when multiple match distdir";

  # Legacy bug: a dep distdir may carry the target's .log_ref. Don't
  # trust a .log_ref whose dist name does not match the distdir -
  # otherwise we would reinstall the wrong distribution. Fall through
  # to cpanm instead (which here resolves Leaked::Dep, matching the
  # distdir) rather than returning "Unrelated-Target" from the leak.
  mkdir "$dir/Leaked-Dep-9.99" or die;
  open my $leak, ">", "$dir/Leaked-Dep-9.99/.log_ref" or die;
  print $leak "X-XY-XYZZY-Unrelated-Target-1.00.tar.gz--1.2.out.gz\n";
  close $leak or die;
  is $c->cpan_path_for("Leaked-Dep-9.99"), "AUTHOR/Leaked-Dep-9.99.tar.gz",
    "cpan_path_for ignores mismatched .log_ref and falls back to cpanm";

  # Fall back to cpanm --info with the dash->colon module name when no
  # log file is available (first-time coverage of a new distdir).
  my $c2 = Devel::Cover::Collection->new(results_dir => tempdir(CLEANUP => 1));
  is $c2->cpan_path_for("Fresh-Dist-1.00"), "AUTHOR/Fresh-Dist-9.99.tar.gz",
    "cpan_path_for falls back to cpanm --info with module name";

  # Strip both "-1.23" and "-v0.2.4" style version suffixes.
  is $c2->cpan_path_for("V-Prefixed-v0.2.4"), "AUTHOR/V-Prefixed-9.99.tar.gz",
    "cpan_path_for strips v-prefixed version suffix";

  # Non-tar.gz CPAN distributions must be parsed from the log filename
  # just like .tar.gz ones; otherwise they fall through to cpanm and
  # incur an extra network call per rebuild candidate.
  my $edir = tempdir(CLEANUP => 1);
  my $ec   = Devel::Cover::Collection->new(results_dir => $edir);
  write_log_ref(
    "$edir/Tgz-Dist-1.00", "T-TG-TGZER-Tgz-Dist-1.00.tgz--111.222.out.gz\n"
  );
  is $ec->cpan_path_for("Tgz-Dist-1.00"), "T/TG/TGZER/Tgz-Dist-1.00.tgz",
    "cpan_path_for parses .tgz from .log_ref";

  touch_empty_file("$edir/Z-ZI-ZIPPER-Zip-Dist-2.00.zip--333.out.gz");
  is $ec->cpan_path_for("Zip-Dist-2.00"), "Z/ZI/ZIPPER/Zip-Dist-2.00.zip",
    "cpan_path_for parses .zip from top-level log filename";

  local $SIG{__WARN__} = sub { };
  is $c2->cpan_path_for("Ghost-0.0"), undef,
    "cpan_path_for returns undef when no log and cpanm fails";

  # Verbose mode must not leak the "dc -> ..." trace into the return.
  my $v = Devel::Cover::Collection->new(
    results_dir => tempdir(CLEANUP => 1),
    verbose     => 1,
  );
  open my $saved, ">&", \*STDERR or die "dup STDERR: $!";
  close STDERR or die "close STDERR: $!";
  open STDERR, ">", \my $err or die "redirect STDERR: $!";
  my $path = $v->cpan_path_for("Clean-Path-1.00");
  open STDERR, ">&", $saved or die "restore STDERR: $!";
  is $path, "AUTHOR/Clean-Path-9.99.tar.gz",
    "cpan_path_for in verbose mode returns clean path (no trace prefix)";
}

sub write_status_method () {
  skip_all "uses fsys which requires alarm" if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);
  my $c   = Devel::Cover::Collection->new(results_dir => $dir);

  $c->write_status(new_count => 4, rebuilt_count => 100, all_rebuilt => 0);

  my $f = "$dir/.cpancover_status";
  ok -e $f, "write_status creates .cpancover_status";
  open my $fh, "<", $f or die "Can't read $f: $!";
  my $content = do { local $/; <$fh> };
  close $fh or die;
  is $content, "all_rebuilt=0\nnew_count=4\nrebuilt_count=100\n",
    "write_status writes sorted key=value lines";

  # When rename fails (here: status path is occupied by a non-empty
  # directory), the temp file must not be left behind to clutter
  # $results_dir and confuse the next caller.
  my $bdir    = tempdir(CLEANUP => 1);
  my $bc      = Devel::Cover::Collection->new(results_dir => $bdir);
  my $blocker = "$bdir/.cpancover_status";
  mkdir $blocker          or die "Can't mkdir $blocker: $!";
  mkdir "$blocker/subdir" or die "Can't mkdir $blocker/subdir: $!";
  local $SIG{__WARN__} = sub { };
  $bc->write_status(new_count => 1);
  opendir my $dh, $bdir or die "Can't opendir $bdir: $!";
  my @leftovers = grep /\A\.cpancover_status\.tmp\./, readdir $dh;
  closedir $dh or die;
  is \@leftovers, [], "write_status cleans up tmp file on rename failure";
}

sub rebuild_pass_method () {
  skip_all "uses fsys which requires alarm" if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);
  my $c   = Devel::Cover::Collection->new(
    results_dir   => $dir,
    rebuild       => 1,
    rebuild_batch => 10,
  );
  is $c->rebuild_pass, 0, "rebuild_pass returns 0 when queue is empty";

  # Queue a distdir, but make cpanm --info fail so cpan_path_for returns
  # undef and rebuild_pass short-circuits without invoking cover_modules.
  # (cover_modules spawns docker-in-docker, which is out of scope for a
  # unit test.)
  my $bin = tempdir(CLEANUP => 1);
  open my $fh, ">", "$bin/cpanm" or die "Can't write stub: $!";
  print $fh "#!/bin/sh\nexit 1\n";
  close $fh or die;
  chmod 0755, "$bin/cpanm" or die;
  local $ENV{PATH}     = "$bin:$ENV{PATH}";
  local $SIG{__WARN__} = sub { };

  mkdir "$dir/Foo-1.0" or die;
  open my $f, ">", "$dir/Foo-1.0/cover.json" or die;
  print $f "{}";
  close $f or die;
  $c->set_failed("Foo-1.0");

  is $c->rebuild_pass, 0,
    "rebuild_pass returns 0 when every cpan_path_for lookup fails";
  ok !-d "$dir/Foo-1.0", "defunct distdir purged by rebuild_pass";
  ok !-e $c->failed_file("Foo-1.0"),
    "defunct distdir's __failed__ marker purged";
}

sub template_provider_fetch () {
  my $provider = Devel::Cover::Collection::Template::Provider->new({});

  for my $name (qw( html summary about module_by_start )) {
    my ($data, $error) = $provider->fetch($name, undef);
    ok defined $data, "template '$name' found";
    ok !$error,       "no error fetching '$name'";
  }

  my ($data, $error) = $provider->fetch("nonexistent_template", undef);
  ok $error, "error for nonexistent template";
}

sub main () {
  #<<<
  my @tests = qw(
    constructor_defaults
    constructor_with_args
    ro_accessors
    rw_accessors
    rwp_accessors
    add_modules
    set_modules
    set_module_file
    process_module_file
    made_res_dir
    path_methods
    status_tracking
    sys_successful_command
    sys_failed_command
    bsys_successful_command
    bsys_failed_command
    fsys_successful_command
    fsys_failed_command
    fbsys_successful_command
    fbsys_failed_command
    sys_timeout
    sys_verbose_output
    bsys_multiline_output
    bsys_stderr_capture
    dc_file
    coverage_class_method
    write_json
    compress_old_versions
    filter_build_dirs_to_targets
    rebuilt_markers
    unflag_all_rebuilt_method
    known_distdirs_method
    all_rebuilt_method
    next_rebuild_batch_method
    status_tracking_rebuild_mode
    cpan_path_for_method
    write_status_method
    rebuild_pass_method
    template_provider_fetch
  );
  #>>>
  for my $test (@tests) {
    no strict qw( refs );
    subtest $test => \&$test;
  }
  done_testing;
}

main;

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.42.0;
use warnings;

use Test::More import => [qw( done_testing is is_deeply like ok subtest )];

use File::Temp qw( tempdir );

use Devel::Cover::Collection ();

sub class_function () {
  my $class = \&Devel::Cover::Collection::class;
  is $class->("n/a"), "na", "class('n/a') -> 'na'";
  is $class->(0),     "c0", "class(0) -> 'c0'";
  is $class->(50),    "c0", "class(50) -> 'c0'";
  is $class->(74.99), "c0", "class(74.99) -> 'c0'";
  is $class->(75),    "c1", "class(75) -> 'c1'";
  is $class->(89.99), "c1", "class(89.99) -> 'c1'";
  is $class->(90),    "c2", "class(90) -> 'c2'";
  is $class->(99.99), "c2", "class(99.99) -> 'c2'";
  is $class->(100),   "c3", "class(100) -> 'c3'";
}

sub constructor_defaults () {
  my $c = Devel::Cover::Collection->new;
  is_deeply $c->build_dirs, [], "build_dirs defaults to empty arrayref";
  is_deeply $c->modules,    [], "modules defaults to empty arrayref";
  is $c->docker,        "docker",     "docker defaults to 'docker'";
  is $c->dryrun,        0,            "dryrun defaults to 0";
  is $c->env,           "prod",       "env defaults to 'prod'";
  is $c->force,         0,            "force defaults to 0";
  is $c->local,         0,            "local defaults to 0";
  is $c->output_file,   "index.html", "output_file defaults to 'index.html'";
  is $c->report,        "html_basic", "report defaults to 'html_basic'";
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
    bin_dir     => "/usr/bin",
    results_dir => "/tmp/results",
    docker      => "podman",
    dryrun      => 1,
    env         => "dev",
    force       => 1,
    local       => 1,
    output_file => "report.html",
    report      => "html_minimal",
    timeout     => 600,
    verbose     => 1,
    workers     => 4
  );
  is $c->bin_dir,     "/usr/bin",     "bin_dir set via constructor";
  is $c->results_dir, "/tmp/results", "results_dir set via constructor";
  is $c->docker,      "podman",       "docker overridden via constructor";
  is $c->dryrun,      1,              "dryrun overridden via constructor";
  is $c->env,         "dev",          "env overridden via constructor";
  is $c->force,       1,              "force overridden via constructor";
  is $c->local,       1,              "local overridden via constructor";
  is $c->output_file, "report.html",  "output_file overridden via constructor";
  is $c->report,      "html_minimal", "report overridden via constructor";
  is $c->timeout,     600,            "timeout overridden via constructor";
  is $c->verbose,     1,              "verbose overridden via constructor";
  is $c->workers,     4,              "workers overridden via constructor";
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
  is_deeply $c->build_dirs, [], "rwp accessor build_dirs readable";
  ok $c->can("_set_build_dirs"), "rwp accessor build_dirs has _set_build_dirs";
  $c->_set_build_dirs([ "/dir1", "/dir2" ]);
  is_deeply $c->build_dirs, [ "/dir1", "/dir2" ],
    "rwp accessor build_dirs settable via _set_build_dirs";
  is_deeply $c->modules, [], "rwp accessor modules readable";
  ok $c->can("_set_modules"), "rwp accessor modules has _set_modules";
  $c->_set_modules(["Foo::Bar"]);
  is_deeply $c->modules, ["Foo::Bar"],
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
  is_deeply $c->modules, [], "modules starts empty";
  $c->add_modules("Foo::Bar");
  is_deeply $c->modules, ["Foo::Bar"], "add_modules adds single module";
  $c->add_modules("Baz::Qux", "Quux::Corge");
  is_deeply $c->modules, [ "Foo::Bar", "Baz::Qux", "Quux::Corge" ],
    "add_modules adds multiple modules";
}

sub set_modules () {
  my $c = Devel::Cover::Collection->new;
  $c->add_modules("Foo::Bar", "Baz::Qux");
  is_deeply $c->modules, [ "Foo::Bar", "Baz::Qux" ], "modules populated";
  $c->set_modules("New::Module");
  is_deeply $c->modules, ["New::Module"], "set_modules replaces all modules";
  $c->set_modules("A", "B", "C");
  is_deeply $c->modules, [ "A", "B", "C" ], "set_modules with multiple modules";
}

sub process_module_file () {
  my $dir  = tempdir(CLEANUP => 1);
  my $file = "$dir/modules.txt";
  open my $fh, ">", $file or die "Can't write $file: $!";
  print $fh <<~'EOT';
    # Comment line
    Foo::Bar
      # Indented comment
    Baz::Qux

    # Empty lines above
    Quux::Corge
    EOT
  close $fh or die "Can't close $file: $!";

  my $c = Devel::Cover::Collection->new(module_file => $file);
  $c->process_module_file;
  is_deeply $c->modules, [ "Foo::Bar", "Baz::Qux", "Quux::Corge" ],
    "process_module_file filters comments and blank lines";

  my $c2 = Devel::Cover::Collection->new;
  $c2->process_module_file;
  is_deeply $c2->modules, [], "process_module_file with undef module_file";

  my $c3 = Devel::Cover::Collection->new(module_file => "");
  $c3->process_module_file;
  is_deeply $c3->modules, [], "process_module_file with empty module_file";

  my $c4 = Devel::Cover::Collection->new(module_file => $file);
  $c4->add_modules("Existing::Module");
  $c4->process_module_file;
  is_deeply $c4->modules,
    [ "Existing::Module", "Foo::Bar", "Baz::Qux", "Quux::Corge" ],
    "process_module_file appends to existing modules";
}

sub made_res_dir () {
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
}

sub path_methods () {
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
  # sys prints short output to stdout (not captured), returns empty on success
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $output = $c->sys("true");
  is $output, "", "sys returns empty string for short successful command";
}

sub sys_failed_command () {
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $output = $c->sys("false");
  is $output, "", "sys returns empty string on failed command";
}

sub bsys_successful_command () {
  # bsys buffers all output (non_buffered=0), so output is captured
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $output = $c->bsys("echo", "buffered output");
  like $output, qr/buffered output/, "bsys captures output";
}

sub bsys_failed_command () {
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $output = $c->bsys("false");
  is $output, "", "bsys returns empty string on failed command";
}

sub fsys_successful_command () {
  # fsys prints short output to stdout (not captured), returns empty on success
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $output = $c->fsys("true");
  is $output, "", "fsys returns empty string for short successful command";
}

sub fsys_failed_command () {
  my $c    = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $died = 0;
  eval {
    $c->fsys("false");
    1;
  } or $died = 1;
  ok $died, "fsys dies on failed command";
}

sub fbsys_successful_command () {
  # fbsys buffers all output (non_buffered=0), so output is captured
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $output = $c->fbsys("echo", "fatal buffered");
  like $output, qr/fatal buffered/, "fbsys captures output";
}

sub fbsys_failed_command () {
  my $c    = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $died = 0;
  eval {
    $c->fbsys("false");
    1;
  } or $died = 1;
  ok $died, "fbsys dies on failed command";
}

sub sys_timeout () {
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 1);
  my $output = $c->sys("sleep", "10");
  is $output, "", "sys returns empty string on timeout";
}

sub sys_verbose_output () {
  # verbose mode adds command prefix to output1 before any output is read
  my $c      = Devel::Cover::Collection->new(verbose => 1, timeout => 10);
  my $output = $c->sys("true");
  like $output, qr/dc -> true/, "sys includes command prefix in verbose mode";
}

sub bsys_multiline_output () {
  # bsys captures all output since non_buffered=0
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $output = $c->bsys("printf", "line1\\nline2\\nline3\\n");
  like $output, qr/line1/, "bsys captures first line";
  like $output, qr/line2/, "bsys captures middle line";
  like $output, qr/line3/, "bsys captures last line";
}

sub bsys_stderr_capture () {
  # _sys redirects stderr to stdout in child, bsys captures it
  my $c      = Devel::Cover::Collection->new(verbose => 0, timeout => 10);
  my $output = $c->bsys("sh", "-c", "echo stderr >&2");
  like $output, qr/stderr/, "bsys captures stderr (redirected to stdout)";
}

sub main () {
  my @tests = qw(
    class_function
    constructor_defaults
    constructor_with_args
    ro_accessors
    rw_accessors
    rwp_accessors
    add_modules
    set_modules
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
  );
  for my $test (@tests) {
    no strict "refs";
    subtest $test => \&$test;
  }
  done_testing;
}

main;

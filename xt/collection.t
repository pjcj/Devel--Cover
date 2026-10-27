#!/usr/bin/perl
# HARNESS-DURATION-LONG

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.42.0;

use Test2::V0 qw(
  dies done_testing is like ok skip_all subtest unlike warnings
);
use File::Temp    qw( tempdir );
use JSON::MaybeXS ();
use POSIX         qw( strftime );

use Devel::Cover::Collection ();

# Stand-in for CPAN::Releases::Latest, whose real index needs the network
our @Latest_paths;
our %Latest_args;
{

  package CPAN::Releases::Latest;
  sub new ($class, %args) { %Latest_args = %args; bless {}, $class }

  sub release_iterator ($self) {
    bless { paths => [@Latest_paths] }, "CPAN::Releases::Latest::Iterator"
  }

  package CPAN::Releases::Latest::Iterator;

  sub next_release ($self) {
    my $path = shift $self->{paths}->@* // return undef;
    bless { path => $path }, "CPAN::Releases::Latest::Release"
  }

  package CPAN::Releases::Latest::Release;
  sub path ($self) { $self->{path} }
}
local $INC{"CPAN/Releases/Latest.pm"} = __FILE__;

# Stand-in for MetaCPAN::Client, whose real scroll needs the network
our @Metacpan_releases;
our @Metacpan_answers;
our %Metacpan_args;
our $Metacpan_total;
{

  package MetaCPAN::Client;
  sub new ($class) { bless {}, $class }

  sub release ($self, $query, $params) {
    %Metacpan_args = (query => $query, params => $params);
    my $releases = shift @Metacpan_answers // [@Metacpan_releases];
    bless { releases => [@$releases] }, "MetaCPAN::Client::ResultSet"
  }

  package MetaCPAN::Client::ResultSet;
  sub total ($self) { $Metacpan_total }

  sub next ($self) {
    my $release = shift $self->{releases}->@* // return undef;
    die "failed to fetch next scrolled batch\n" if $release eq "die";
    bless {%$release}, "MetaCPAN::Client::Release"
  }

  package MetaCPAN::Client::Release;
  sub name         ($self) { $self->{name} }
  sub date         ($self) { $self->{date} }
  sub status       ($self) { $self->{status} }
  sub maturity     ($self) { $self->{maturity} }
  sub download_url ($self) { $self->{download_url} }
  sub stat         ($self) { $self->{stat} }
}
local $INC{"MetaCPAN/Client.pm"} = __FILE__;

# Stand-in for File::HomeDir, whose real data directory is under $HOME
our @Homedir_args;
our $Homedir_dir;
{

  package File::HomeDir;

  sub my_dist_data ($class, @args) {
    @Homedir_args   = @args;
    $Homedir_dir  //= File::Temp::tempdir(CLEANUP => 1)
  }
}
local $INC{"File/HomeDir.pm"} = __FILE__;

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
  is $c->mark_rebuilt,  0,            "mark_rebuilt defaults to 0";
  is $c->latest_index,  undef,        "latest_index defaults to undef";
  is $c->retry_delay,   1,            "retry_delay defaults to 1";
  is $c->report,        "html",       "report defaults to 'html'";
  is $c->timeout,       60 * 60,      "timeout defaults to 3600 (60 minutes)";
  is $c->verbose,       0,            "verbose defaults to 0";
  is $c->workers,       0,            "workers defaults to 0";
  is ref($c->cpan_dir), "ARRAY",      "cpan_dir is an arrayref";
  is $c->bin_dir,       undef,        "bin_dir is undef by default";
  is $c->results_dir,   undef,        "results_dir is undef by default";
  is $c->module_file,   undef,        "module_file is undef by default";
  is $c->dir,           undef,        "dir is undef by default";
  is $c->file,          undef,        "file is undef by default";

  is $c->distdir_for, {}, "distdir_for defaults to empty hashref";
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
    mark_rebuilt  => 1,
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
  is $c->mark_rebuilt,  1,              "mark_rebuilt overridden";
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

sub internal_accessors () {
  my $c = Devel::Cover::Collection->new(
    build_dirs  => ["/dir1", "/dir2"],
    distdir_for => { "/dir1" => "Foo-1.0" },
    modules     => ["Foo::Bar"],
    module_file => "/tmp/modules.txt",
  );
  is $c->build_dirs, ["/dir1", "/dir2"], "build_dirs set via constructor";
  is $c->distdir_for, { "/dir1" => "Foo-1.0" },
    "distdir_for set via constructor";
  is $c->modules,     ["Foo::Bar"],       "modules set via constructor";
  is $c->module_file, "/tmp/modules.txt", "module_file set via constructor";
  ok !$c->can("_set_build_dirs"),  "build_dirs has no private setter";
  ok !$c->can("_set_modules"),     "modules has no private setter";
  ok !$c->can("_set_module_file"), "module_file has no private setter";
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

sub module_name_version () {
  my $c = Devel::Cover::Collection->new;

  my %parsed = (
    "Foo-1.2"            => ["Foo",       "1.2"],
    "Foo-1.2.3"          => ["Foo",       "1.2.3"],
    "Foo-v1.2.3"         => ["Foo",       "v1.2.3"],
    "Foo-Bar-0.10.6"     => ["Foo-Bar",   "0.10.6"],
    "Foo-1.2_01"         => ["Foo",       "1.2_01"],
    "Perl-Tidy-20240903" => ["Perl-Tidy", "20240903"],
    "Foo-1.2-TRIAL"      => ["Foo",       "1.2-TRIAL"],
  );
  for my $module (sort keys %parsed) {
    is [$c->_module_name_version({}, $module)], $parsed{$module},
      "$module parses to name and version";
  }

  is [$c->_module_name_version({}, "Foo")], ["Foo", undef],
    "a distdir with no version yields an undef version";
  is [
    $c->_module_name_version(
      { name => "Real-Name", version => "9.9" }, "Foo-1.2",
    ),
    ],
    ["Foo", "1.2"], "the release name and version win over the metadata";
  is [
    $c->_module_name_version(
      { name => "Real-Name", version => "9.9" }, "Foo",
    ),
    ],
    ["Foo", undef],
    "a distdir without a version never takes a name from the metadata";
  is [$c->_module_name_version({ name => "Foo", version => "9.9" }, "Foo")],
    ["Foo", "9.9"],
    "a distdir without a version takes the version of a run with its own name";
  is [
    $c->_module_name_version(
      { name => "Foo", version => "1.2" },
      "Foo-1.2-TRIAL",
    ),
    ],
    ["Foo", "1.2-TRIAL"], "a TRIAL keeps its suffix over the recorded version";
  is [
    $c->_module_name_version(
      { name => "/build/Foo-1.2.3", version => "unknown" }, "Foo-1.2.3",
    ),
    ],
    ["Foo", "1.2.3"], "a run directory path as name is discarded";
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
      "Foo-Baz-v1.2.3" => {
        module => { module => "Foo-Baz-v1.2.3" },
        total  => { pc     => "50.00" },
      },
      Das => {
        module => { module => "Das", name => "Das", version => "0.5" },
        total  => { pc     => "60.00" },
      },
      Evil => {
        module => { module => "Evil", name => "Moose", version => "2.2207" },
        total  => { pc     => "10.00" },
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
  like $content,   qr/"Foo-Baz"/, "JSON contains name parsed from the distdir";
  like $content, qr/"v1\.2\.3"/,
    "JSON contains a three-part version parsed from the distdir";
  like $content,   qr/"Das"/,   "JSON contains a versionless release";
  like $content,   qr/"0\.5"/,  "JSON contains the version of its own run";
  unlike $content, qr/"Moose"/, "JSON never takes a name from the metadata";
  unlike $content, qr/"Evil"/,  "JSON omits a release left with no version";
}

sub set_age ($file, $age) {
  my $time = time - $age;
  utime $time, $time, $file or die "Can't utime $file: $!";
  $time
}

# Make a cache directory, with cache file and marker $age seconds old if defined
sub cache_dir ($age) {
  my $dir = tempdir(CLEANUP => 1);
  return $dir unless defined $age;
  my $file = "$dir/latest-releases.txt";
  for my $path ($file, "$file.full") {
    open my $fh, ">", $path or die "Can't write $path: $!";
    print $fh "#FORMAT: 1\n" if $path eq $file;
    close $fh or die "Can't close $path: $!";
    set_age($path, $age);
  }
  $dir
}

sub compress_output ($c, $versions) {
  my $outfile = $c->results_dir . "/compress_output.txt";
  {
    open my $saved, ">&", STDOUT   or die "Can't dup STDOUT: $!";
    open STDOUT,    ">",  $outfile or die "Can't redirect STDOUT: $!";
    $c->compress_old_versions($versions);
    open STDOUT, ">&", $saved or die "Can't restore STDOUT: $!";
  }
  open my $fh, "<", $outfile or die "Can't read $outfile: $!";
  my $output = do { local $/; <$fh> };
  close $fh or die "Can't close $outfile: $!";
  $output
}

sub compress_old_versions () {
  skip_all "uses fsys which requires alarm (not available on Windows)"
    if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);

  # Reproduce GH-409: CPAN versions that sort incorrectly when numified.
  # 0.41 numifies to 0.410, less than 0.700/0.800/0.900, so the latest
  # release was compressed and removed under the old version-based sort.
  my @versions = (
    { dir => "0.5-TRIAL", ver   => "0.5", start => 500 },
    { ver => "0.7",       start => 1000 },
    { ver => "0.8",       start => 2000 },
    { ver => "0.9",       start => 3000 },
    { ver => "0.41",      start => 4000 },
  );

  my $json = JSON::MaybeXS->new(utf8 => 1);
  for my $v (@versions) {
    my $mod_dir = "$dir/Net-RDAP-" . ($v->{dir} // $v->{ver});
    mkdir $mod_dir or die "Can't mkdir $mod_dir: $!";
    my $cover = { runs =>
      [{ name => "Net-RDAP", version => $v->{ver}, start => $v->{start} }] };
    open my $fh, ">", "$mod_dir/cover.json" or die "Can't write: $!";
    print $fh $json->encode($cover);
    close $fh or die "Can't close: $!";
  }

  # entries the scan must skip: invalid JSON and a missing cover.json
  my $broken = "$dir/Net-RDAP-0.6";
  mkdir $broken or die "Can't mkdir $broken: $!";
  open my $bfh, ">", "$broken/cover.json" or die "Can't write: $!";
  print $bfh "not json";
  close $bfh                or die "Can't close: $!";
  mkdir "$dir/Net-RDAP-0.3" or die "Can't mkdir: $!";

  local $Homedir_dir = cache_dir(0);
  my $c      = Devel::Cover::Collection->new(results_dir => $dir, dryrun => 1);
  my $output = compress_output($c, 3);

  # 5 versions, keep 3: the oldest two by start time should be compressed
  like $output, qr/^compressing Net-RDAP-0\.7$/m,
    "oldest version by start time is compressed";
  like $output, qr/^compressing Net-RDAP-0\.5-TRIAL$/m,
    "an old TRIAL is compressed like any other version";
  unlike $output, qr/^compressing Net-RDAP-0\.41$/m,
    "latest release is kept (was removed by numeric version sort)";
  unlike $output, qr/^compressing Net-RDAP-0\.9$/m,
    "recent version 0.9 is kept";
  unlike $output, qr/^compressing Net-RDAP-0\.8$/m,
    "recent version 0.8 is kept";
  unlike $output, qr/^compressing Net-RDAP-0\.6$/m,
    "a distdir with invalid JSON is skipped";
  unlike $output, qr/^compressing Net-RDAP-0\.3$/m,
    "a distdir without cover.json is skipped";
}

sub make_distdir ($dir, $distdir, $name, $start) {
  my $path = "$dir/$distdir";
  mkdir $path or die "Can't mkdir $path: $!";
  my $cover = { runs => [{ name => $name, start => $start }] };
  open my $fh, ">", "$path/cover.json" or die "Can't write: $!";
  print $fh JSON::MaybeXS->new(utf8 => 1)->encode($cover);
  close $fh or die "Can't close: $!";
}

sub make_foo_distdirs ($dir) {
  my $starts = {
    "Foo-1.9"        => 500,
    "Foo-2.0"        => 1000,
    "Foo-2.01-TRIAL" => 2000,
    "Foo-2.02-TRIAL" => 3000,
    "Foo-2.03-TRIAL" => 4000,
  };
  make_distdir($dir, $_, "Foo", $starts->{$_}) for sort keys %$starts;
}

sub compress_old_versions_keeps_latest () {
  skip_all "uses fsys which requires alarm (not available on Windows)"
    if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);
  make_foo_distdirs($dir);
  local @Latest_paths = qw(
    A/AU/AUTHOR/Foo-2.0.tar.gz
    A/AU/AUTHOR/Foo-2.03-TRIAL.tar.gz
  );
  local $Homedir_dir = cache_dir(0);
  my $c      = Devel::Cover::Collection->new(results_dir => $dir, dryrun => 1);
  my $output = compress_output($c, 3);

  like $output, qr/^compressing Foo-1\.9$/m,
    "an old release outside the index is compressed";
  unlike $output, qr/^compressing Foo-2\.0$/m,
    "a release in the index is kept behind three newer TRIALs";
  unlike $output, qr/^compressing Foo-2\.0[1-3]-TRIAL$/m,
    "the three newest TRIALs are kept";
}

sub compress_old_versions_unreadable_index () {
  skip_all "uses fsys which requires alarm (not available on Windows)"
    if $Is_win32;
  my $dir = tempdir(CLEANUP => 1);
  make_foo_distdirs($dir);
  my $c = Devel::Cover::Collection->new(results_dir => $dir, dryrun => 1);

  no warnings "redefine";
  local *Devel::Cover::Collection::latest_paths = sub { die "no index\n" };
  my $output;
  my $warnings = warnings { $output = compress_output($c, 3) };
  unlike $output, qr/^compressing /m, "nothing is compressed without the index";
  is @$warnings, 1, "one warning when the index can't be read";
  is $warnings->[0],
    "Can't read the CPAN release index, compressing nothing: no index\n",
    "the warning gives the index error";
}

my $Has_yaml = eval { require YAML; 1 };

sub write_state_file ($build_dir, $id) {
  my $dist = { build_dir => $build_dir };
  $dist->{ID} = $id if defined $id;
  YAML::DumpFile(
    "$build_dir.yml", {
      distribution => bless($dist, "CPAN::Distribution"),
      perl         => { '$^X' => $^X },
      time         => time,
    },
  );
}

sub build_dir_id () {
  skip_all "YAML required" unless $Has_yaml;
  my $c   = Devel::Cover::Collection->new;
  my $dir = tempdir(CLEANUP => 1);
  my $id  = "D/DT/DTUCKWELL/Acme-DTUCKWELL-Utils-0.04.tar.gz";

  my $bd = "$dir/Acme-DTUCKWELL-Utils-0.03-0";
  mkdir $bd or die "Can't mkdir $bd: $!";
  write_state_file($bd, $id);
  is $c->build_dir_id($bd), $id,
    "build_dir_id reads the ID from the state file";

  my $no_id = "$dir/No-Id-1.0-0";
  mkdir $no_id or die "Can't mkdir $no_id: $!";
  write_state_file($no_id, undef);
  is $c->build_dir_id($no_id), undef,
    "build_dir_id is undef when the state file has no ID";

  my $no_file = "$dir/No-File-1.0-0";
  mkdir $no_file or die "Can't mkdir $no_file: $!";
  is $c->build_dir_id($no_file), undef,
    "build_dir_id is undef when there is no state file";

  my $bad = "$dir/Bad-1.0-0";
  mkdir $bad or die "Can't mkdir $bad: $!";
  open my $fh, ">", "$bad.yml" or die "Can't open $bad.yml: $!";
  print $fh "- [unterminated\n";
  close $fh or die "Can't close $bad.yml: $!";
  is $c->build_dir_id($bad), undef,
    "build_dir_id is undef when the state file does not parse";
}

sub build_dir_id_from_cpan () {
  skip_all "YAML required" unless $Has_yaml;
  require CPAN;
  skip_all "CPAN::Distribution->store_persistent_state required"
    unless CPAN::Distribution->can("store_persistent_state");

  my $dir = tempdir(CLEANUP => 1);
  my $bd  = "$dir/Acme-DTUCKWELL-Utils-0.03-0";
  mkdir $bd or die "Can't mkdir $bd: $!";
  my $id = "D/DT/DTUCKWELL/Acme-DTUCKWELL-Utils-0.04.tar.gz";

  local $CPAN::Config->{build_dir} = $dir;
  local $CPAN::Frontend = "CPAN::Shell";
  $CPAN::META //= CPAN->new;
  my $dist = bless { ID => $id, build_dir => $bd }, "CPAN::Distribution";
  $dist->store_persistent_state;
  ok -e "$bd.yml", "CPAN.pm writes the state file beside the build dir";

  my $c = Devel::Cover::Collection->new;
  is $c->build_dir_id($bd), $id,
    "build_dir_id reads the ID from a state file CPAN.pm wrote";
}

sub make_build_dir ($dir, $name, $id = undef) {
  my $bd = "$dir/$name";
  mkdir $bd or die "Can't mkdir $bd: $!";
  write_state_file($bd, $id) if defined $id;
  $bd
}

sub filter_build_dirs_to_targets () {
  skip_all "YAML required" unless $Has_yaml;
  my $dir     = tempdir(CLEANUP => 1);
  my $utils   = "D/DT/DTUCKWELL/Acme-DTUCKWELL-Utils-0.04.tar.gz";
  my $owa     = "A/AU/AUTHOR/Apache-OWA-0.7.tar.gz";
  my $behind  = make_build_dir($dir, "Acme-DTUCKWELL-Utils-0.03-0", $utils);
  my $renamed = make_build_dir($dir, "OWA-0",                       $owa);
  my $dep
    = make_build_dir($dir, "PPI-1.280-0", "M/MI/MITHALDU/PPI-1.280.tar.gz");
  my $stale = make_build_dir($dir, "Stale-1.0-0");

  my $c = Devel::Cover::Collection->new(
    modules    => [$utils,  $owa],
    build_dirs => [$behind, $renamed, $dep, $stale],
  );
  my $w = warnings { $c->filter_build_dirs_to_targets };

  is $c->build_dirs, [$behind, $renamed],
    "filter keeps the build dirs whose state file ID names a target";
  is $c->distdir_for,
    { $behind => "Acme-DTUCKWELL-Utils-0.04", $renamed => "Apache-OWA-0.7" },
    "filter records the target distdir name for each kept build dir";
  is @$w, 1, "one warning for the build dir without a state file";
  like $w->[0], qr/\Q$stale\E/, "the warning names the build dir";

  my $id  = "T/TA/TAR/Target-1.0.tar.gz";
  my @all = map make_build_dir($dir, "Target-1.0-$_", $id), 0 .. 2;
  my $c2
    = Devel::Cover::Collection->new(modules => [$id], build_dirs => [@all]);
  $c2->filter_build_dirs_to_targets;
  is $c2->build_dirs, [@all], "filter keeps all reinstall attempts of a target";

  my $c3 = Devel::Cover::Collection->new(build_dirs => [$dep]);
  $c3->filter_build_dirs_to_targets;
  is $c3->build_dirs, [], "filter empties build_dirs when modules is empty";

  my $c4 = Devel::Cover::Collection->new(
    modules    => ["A/AU/AUTHOR/Foo-1.0.tar.gz"],
    build_dirs => [$dep],
  );
  my $err = dies { $c4->filter_build_dirs_to_targets };
  like $err, qr{A/AU/AUTHOR/Foo-1\.0\.tar\.gz},
    "filter dies naming a target with no build dir";
  like $err, qr/\Q$dep\E/, "the error lists the build dirs seen";

  my $c5 = Devel::Cover::Collection->new(
    modules    => ["A/AU/AUTHOR/Foo-1.0.tar.gz"],
    build_dirs => [],
  );
  like dies { $c5->filter_build_dirs_to_targets }, qr/Foo-1\.0/,
    "filter dies when there are no build dirs for a target";
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

sub make_covered ($dir, $d) {
  mkdir "$dir/$d" or die "Can't mkdir $dir/$d: $!";
  open my $fh, ">", "$dir/$d/cover.json" or die "Can't write cover.json: $!";
  print $fh "{}";
  close $fh or die "Can't close cover.json: $!";
}

sub cpan_release ($path, $mtime, %extra) {
  +{
    name         => "Unnamed",
    date         => "2026-10-21T00:00:00",
    status       => "latest",
    maturity     => "released",
    download_url => "https://cpan.metacpan.org/authors/id/$path",
    stat         => { mtime => $mtime, size => 10 * $mtime },
    %extra,
  }
}

sub slurp ($file) {
  open my $fh, "<", $file or die "Can't read $file: $!";
  local $/;
  <$fh>
}

sub fetches ($c, %options) {
  local %Metacpan_args;
  $c->latest_paths(%options);
  %Metacpan_args ? 1 : 0
}

sub latest_paths_method () {
  local @Latest_paths = qw(
    A/AU/AUTHOR/Alpha-1.0.tar.gz
    B/BR/BRAVO/Bravo-2.0-TRIAL.tar.gz
  );
  my $fetched = "C/CH/CHARLIE/Charlie-1.0.tar.gz";
  local @Metacpan_releases = cpan_release($fetched, 5);
  local $Metacpan_total    = 1;
  local %Latest_args;
  local $Homedir_dir = cache_dir(0);
  my $c = Devel::Cover::Collection->new;

  is [$c->latest_paths], \@Latest_paths,
    "latest_paths returns every release path in the index";
  is \%Latest_args, { path => "$Homedir_dir/latest-releases.txt" },
    "latest_paths reads the CPAN::Releases::Latest cache file by default";
  Devel::Cover::Collection->new(latest_index => "index.txt")->latest_paths;
  is \%Latest_args, { path => "index.txt" },
    "latest_index is passed as the index file";
  {
    local $ENV{CPANCOVER_LATEST_INDEX} = "env.txt";
    Devel::Cover::Collection->new->latest_paths;
  }
  is \%Latest_args, { path => "env.txt" },
    "CPANCOVER_LATEST_INDEX sets the default index file";

  {
    local $Homedir_dir = cache_dir(undef);
    is $c->full_index_age, undef, "a missing cache file has no full fetch age";
    is fetches($c),        1,     "a missing cache file is fetched";
    is slurp("$Homedir_dir/latest-releases.txt"),
      "#FORMAT: 1\nCharlie $fetched 5 50\n",
      "the fetched releases are written to the cache file";
    ok !-e "$Homedir_dir/latest-releases.txt.full",
      "a full fetch leaves a missing marker missing";
  }
  {
    local $Homedir_dir = cache_dir(0);
    is fetches($c), 0, "a fresh cache file is read without a fetch";
  }
  {
    local $Homedir_dir = cache_dir(0);
    set_age($c->latest_index_path, 2 * 24 * 60 * 60);
    my $mtime = set_age($c->full_index_path, 2 * 24 * 60 * 60);
    is fetches($c), 1, "a cache file two days old is fetched again";
    is +(stat $c->full_index_path)[9], $mtime,
      "a full fetch leaves the marker mtime alone";
  }
  {
    local $Homedir_dir = cache_dir(0);
    unlink $c->full_index_path or die "Can't unlink the marker: $!";
    is $c->full_index_age, undef, "a missing marker has no full fetch age";
    is fetches($c), 0,
      "a fresh cache file without a marker is read without a fetch";
  }
  {
    local $Homedir_dir = cache_dir(0);
    is fetches($c, max_age => 0), 1, "max_age 0 fetches a fresh cache file";
  }
  my $set = Devel::Cover::Collection->new(latest_index => "index.txt");
  is fetches($set, max_age => 0), 0, "a latest_index file is never fetched";

  is $c->latest_index_path, "$Homedir_dir/latest-releases.txt",
    "latest_index_path defaults to the CPAN::Releases::Latest cache file";
  is \@Homedir_args, ["CPAN-Releases-Latest", { create => 1 }],
    "latest_index_path asks File::HomeDir for the module data directory";
  is $set->latest_index_path, "index.txt",
    "latest_index_path returns latest_index when set";
  is $c->full_index_path, "$Homedir_dir/latest-releases.txt.full",
    "full_index_path names the marker beside the cache file";

  my $missing = tempdir(CLEANUP => 1) . "/missing/latest-releases.txt";
  like dies {
    Devel::Cover::Collection->new(latest_index => $missing)->mark_full_index
  }, qr|^Can't open \Q$missing\E\.full: |,
    "mark_full_index dies when it cannot open the marker";
}

sub fetch_latest_releases_method () {
  my $trial    = "A/AU/AUTHOR/Alpha-2.1-TRIAL.tar.gz";
  my $scroll   = "failed to fetch next scrolled batch\n";
  my @releases = (
    cpan_release("A/AU/AUTHOR/Alpha-1.0.tar.gz", 100),
    cpan_release("A/AU/AUTHOR/Alpha-2.0.tar.gz", 300),
    cpan_release("A/AU/AUTHOR/Alpha-1.5.tar.gz", 200),
    cpan_release($trial, 400, status => "cpan", maturity => "developer"),
    cpan_release("B/BR/BRAVO/Bravo-1.0.tar.gz", 150, download_url => undef),
    cpan_release("C/CH/CHARLIE/charlie.pm.gz",  250, name         => "Charlie"),
  );
  my $expected = {
    released => {
      Alpha =>
        { path => "A/AU/AUTHOR/Alpha-2.0.tar.gz", time => 300, size => 3000 },
      Charlie =>
        { path => "C/CH/CHARLIE/charlie.pm.gz", time => 250, size => 2500 },
    },
    developer => { Alpha => { path => $trial, time => 400, size => 4000 } },
  };
  local @Metacpan_releases = @releases;
  local $Metacpan_total    = @releases;
  local %Metacpan_args;
  my $c = Devel::Cover::Collection->new(retry_delay => 0);

  is $c->fetch_latest_releases, $expected,
    "fetch_latest_releases keeps the newest release of each maturity";
  is \%Metacpan_args, {
      query => {
        either => [
          { all => [{ status => "latest" }, { maturity => "released" }] },
          { all => [{ status => "cpan" },   { maturity => "developer" }] },
        ],
      },
      params => {
        _source => [qw( name version date status maturity stat download_url )],
      },
    },
    "fetch_latest_releases asks for latest and developer releases";

  local @Metacpan_releases = ($releases[0], "die", @releases[1 .. $#releases]);
  my $w = warnings {
    is $c->fetch_latest_releases, $expected, "a failed request is sent again"
  };
  is $w, ["Retrying the CPAN release list after: $scroll"],
    "a failed request gives one warning";

  local @Metacpan_releases = (("die") x 10, @releases);
  $w = warnings {
    is dies { $c->fetch_latest_releases }, $scroll,
      "ten failed requests in a row die with the scroll error"
  };
  is @$w, 9, "every failure before the last gives a warning";

  local @Metacpan_releases = @releases;
  local $Metacpan_total    = @releases + 1;
  like dies { $c->fetch_latest_releases },
    qr/^CPAN release list ended early: got 6 of 7$/,
    "a list shorter than the total dies";

  my $old    = cpan_release("O/OL/OLD/Old-1.0.tar.gz", 50, status => "backpan");
  my $ignore = "CPAN release list ignores the query";
  my $bad    = "$ignore: backpan released Unnamed\n";
  local $Metacpan_total   = @releases;
  local @Metacpan_answers = ([$old, @releases]);

  $w = warnings {
    is $c->fetch_latest_releases, $expected,
      "an answer that ignores the query is fetched again"
  };
  is $w, ["Retrying the CPAN release list after: $bad"],
    "an answer that ignores the query gives one warning";

  local @Metacpan_answers = ([$old]) x 10;
  $w = warnings {
    is dies { $c->fetch_latest_releases }, $bad,
      "ten answers that ignore the query die"
  };
  is @$w, 9, "every ignored query before the last gives a warning";

  my $late = cpan_release("D/DE/DELTA/Delta-1.0.tar.gz", 60, status => "cpan");
  local @Metacpan_answers = ([@releases, $late], \@releases);
  $w = warnings {
    is dies { $c->fetch_latest_releases }, "$ignore: cpan released Unnamed\n",
      "a later release that ignores the query dies"
  };
  is $w, [], "a later release that ignores the query is not retried";
  is \@Metacpan_answers, [\@releases],
    "a later release that ignores the query sends one search";

  local @Metacpan_answers = ([]);
  local $Metacpan_total   = 0;
  is $c->fetch_latest_releases, { released => {}, developer => {} },
    "an empty release list gives no releases";

  my $since  = 1_792_454_400;
  my $recent = cpan_release("E/EC/ECHO/Echo-1.0.tar.gz", 500);
  my $stale  = cpan_release(
    "G/GO/GOLF/Golf-1.0.tar.gz", 600, date => "2026-10-19T23:59:59",
  );
  my $echo = { path => "E/EC/ECHO/Echo-1.0.tar.gz", time => 500, size => 5000 };
  local @Metacpan_answers = ([$recent]);
  local $Metacpan_total   = 1;

  is $c->fetch_latest_releases(since => $since),
    { released => { Echo => $echo }, developer => {} },
    "fetch_latest_releases with since returns the newer releases";
  is $Metacpan_args{params}, {
      _source   => [qw( name version date status maturity stat download_url )],
      es_filter => { range => { date => { gte => "2026-10-20T00:00:00" } } },
    },
    "since asks for releases uploaded from that time";

  local @Metacpan_answers = ([$recent, $stale]);
  local $Metacpan_total   = 2;
  is dies { $c->fetch_latest_releases(since => $since) },
    "$ignore: latest released Unnamed\n", "a release from before since dies";
}

sub metacpan_release ($status, $maturity, $date = "2026-10-21T00:00:00") {
  bless { status => $status, maturity => $maturity, date => $date },
    "MetaCPAN::Client::Release"
}

sub release_matches_method () {
  my $c = Devel::Cover::Collection->new;
  ok $c->release_matches(metacpan_release(qw( latest released ))),
    "release_matches accepts a latest stable release";
  ok $c->release_matches(metacpan_release(qw( cpan developer ))),
    "release_matches accepts a developer release on CPAN";
  ok !$c->release_matches(metacpan_release(qw( latest developer ))),
    "release_matches rejects a latest developer release";
  ok !$c->release_matches(metacpan_release(qw( cpan released ))),
    "release_matches rejects a stable release that is not the latest";
  ok !$c->release_matches(metacpan_release(qw( backpan released ))),
    "release_matches rejects a release on BackPAN";
  my $since = "2026-10-21T00:00:00";
  my $old   = metacpan_release(qw( latest released 2026-10-20T23:59:59 ));
  ok $c->release_matches(metacpan_release(qw( latest released )), $since),
    "release_matches accepts a release uploaded at the since time";
  ok !$c->release_matches($old, $since),
    "release_matches rejects a release uploaded before the since time";
}

sub index_entry ($path, $time) { +{ path => $path, time => $time, size => 7 } }

sub write_latest_index_method () {
  my $dir      = tempdir(CLEANUP => 1);
  my $index    = "$dir/latest-releases.txt";
  my $releases = {
    released => {
      Stable => index_entry("S/ST/STABLE/Stable-1.0.tar.gz", 100),
      Newer  => index_entry("N/NE/NEWER/Newer-1.0.tar.gz",   100),
      Older  => index_entry("O/OL/OLDER/Older-2.0.tar.gz",   300),
      apple  => index_entry("A/AP/APPLE/apple-1.0.tar.gz",   100),
      Banana => index_entry("B/BA/BANANA/Banana-1.0.tar.gz", 100),
    },
    developer => {
      Dev   => index_entry("D/DE/DEV/Dev-0.1-TRIAL.tar.gz",     200),
      Newer => index_entry("N/NE/NEWER/Newer-1.1-TRIAL.tar.gz", 200),
      Older => index_entry("O/OL/OLDER/Older-1.9-TRIAL.tar.gz", 200),
    },
  };
  my $c = Devel::Cover::Collection->new(latest_index => $index);
  $c->write_latest_index($releases);

  open my $fh, "<", $index or die "Can't read $index: $!";
  my $text = do { local $/; <$fh> };
  close $fh or die;
  is $text,
    join("",
      "#FORMAT: 1\n",
      "apple A/AP/APPLE/apple-1.0.tar.gz 100 7\n",
      "Banana B/BA/BANANA/Banana-1.0.tar.gz 100 7\n",
      "Dev D/DE/DEV/Dev-0.1-TRIAL.tar.gz 200 7\n",
      "Newer N/NE/NEWER/Newer-1.0.tar.gz 100 7\n",
      "Newer N/NE/NEWER/Newer-1.1-TRIAL.tar.gz 200 7\n",
      "Older O/OL/OLDER/Older-2.0.tar.gz 300 7\n",
      "Stable S/ST/STABLE/Stable-1.0.tar.gz 100 7\n",
    ),
    "write_latest_index writes the CPAN::Releases::Latest format";

  opendir my $dh, $dir or die "Can't opendir $dir: $!";
  my @leftovers = grep /\.tmp\./, readdir $dh;
  closedir $dh or die;
  is \@leftovers, [], "write_latest_index leaves no temporary file";

  my $missing = "$dir/missing/latest-releases.txt";
  like dies {
    Devel::Cover::Collection->new(latest_index => $missing)
      ->write_latest_index($releases)
  }, qr|^Can't open \Q$missing\E\.tmp\.$$: |,
    "write_latest_index dies when it cannot open the file";

  my $blocker = "$dir/blocker";
  mkdir $blocker          or die "Can't mkdir $blocker: $!";
  mkdir "$blocker/subdir" or die "Can't mkdir $blocker/subdir: $!";
  like dies {
    Devel::Cover::Collection->new(latest_index => $blocker)
      ->write_latest_index($releases)
  }, qr|^Can't rename \Q$blocker\E\.tmp\.$$ to \Q$blocker\E: |,
    "write_latest_index dies when it cannot replace the index";
}

sub read_latest_index_method () {
  my $dir      = tempdir(CLEANUP => 1);
  my $index    = "$dir/latest-releases.txt";
  my $releases = {
    released => {
      Stable => index_entry("S/ST/STABLE/Stable-1.0.tar.gz", 100),
      Both   => index_entry("B/BO/BOTH/Both-1.0.tar.gz",     100),
    },
    developer => {
      Dev   => index_entry("D/DE/DEV/Dev-0.1-TRIAL.tar.gz",   200),
      Both  => index_entry("B/BO/BOTH/Both-1.1-TRIAL.tar.gz", 200),
      Hotel => index_entry("H/HO/HOTEL/Hotel-1.00_01.tar.gz", 300),
    },
  };
  my $c = Devel::Cover::Collection->new(latest_index => $index);
  $c->write_latest_index($releases);
  is $c->read_latest_index, $releases,
    "read_latest_index reads what write_latest_index writes";

  my $missing = "$dir/missing.txt";
  like dies {
    Devel::Cover::Collection->new(latest_index => $missing)->read_latest_index
  }, qr|^Can't open \Q$missing\E: |,
    "read_latest_index dies when it cannot open the file";

  for my $text ("", "#FORMAT: 2\n") {
    open my $fh, ">", $index or die "Can't write $index: $!";
    print $fh $text;
    close $fh or die "Can't close $index: $!";
    is dies { $c->read_latest_index }, "Unknown format in $index\n",
      "read_latest_index dies on an unknown format";
  }
}

sub get_latest_output ($c) {
  my $out = "";
  local *STDOUT;
  open STDOUT, ">", \$out or die "Can't redirect STDOUT: $!";
  $c->get_latest;
  $out
}

sub get_latest_recent () {
  local $Homedir_dir = cache_dir(0);
  my $c = Devel::Cover::Collection->new;
  $c->write_latest_index({
    released => {
      Alpha => index_entry("A/AU/AUTHOR/Alpha-1.0.tar.gz", 100),
      Bravo => index_entry("B/BR/BRAVO/Bravo-1.0.tar.gz",  100),
      Delta => index_entry("D/DE/DELTA/Delta-1.0.tar.gz",  300),
      Echo  => index_entry("E/EC/ECHO/Echo-1.0.tar.gz",    100),
    },
    developer => {},
  });
  my $mtime = set_age($c->full_index_path, 2 * 60 * 60);
  my $now   = strftime("%Y-%m-%dT%H:%M:%S", gmtime);
  local @Metacpan_releases = (
    cpan_release("B/BR/BRAVO/Bravo-2.0.tar.gz",     200, date => $now),
    cpan_release("C/CH/CHARLIE/Charlie-1.0.tar.gz", 250, date => $now),
    cpan_release("D/DE/DELTA/Delta-1.0.tar.gz",     300, date => $now),
    cpan_release(
      "A/AU/AUTHOR/Alpha-1.1-TRIAL.tar.gz", 90,
      date     => $now,
      status   => "cpan",
      maturity => "developer",
    ),
    cpan_release(
      "E/EC/ECHO/Echo-1.1-TRIAL.tar.gz", 400,
      date     => $now,
      status   => "cpan",
      maturity => "developer",
    ),
  );
  local $Metacpan_total = @Metacpan_releases;
  local @Latest_paths   = qw(
    A/AU/AUTHOR/Alpha-1.0.tar.gz
    B/BR/BRAVO/Bravo-2.0.tar.gz
    C/CH/CHARLIE/Charlie-1.0.tar.gz
    D/DE/DELTA/Delta-1.0.tar.gz
    E/EC/ECHO/Echo-1.0.tar.gz
    E/EC/ECHO/Echo-1.1-TRIAL.tar.gz
  );
  local %Metacpan_args;

  is get_latest_output($c), join("", map "$_\n", @Latest_paths[1 .. 3, 5]),
    "get_latest prints only the recent current paths";
  my $since = strftime("%Y-%m-%dT%H:%M:%S", gmtime($mtime - 24 * 60 * 60));
  is $Metacpan_args{params}{es_filter},
    { range => { date => { gte => $since } } },
    "get_latest fetches releases since a day before the full fetch";
  is slurp($c->latest_index_path),
    join("",
      "#FORMAT: 1\n",
      "Alpha A/AU/AUTHOR/Alpha-1.0.tar.gz 100 7\n",
      "Bravo B/BR/BRAVO/Bravo-2.0.tar.gz 200 2000\n",
      "Charlie C/CH/CHARLIE/Charlie-1.0.tar.gz 250 2500\n",
      "Delta D/DE/DELTA/Delta-1.0.tar.gz 300 7\n",
      "Echo E/EC/ECHO/Echo-1.0.tar.gz 100 7\n",
      "Echo E/EC/ECHO/Echo-1.1-TRIAL.tar.gz 400 4000\n",
    ),
    "get_latest merges the recent releases into the cache file";
  is +(stat $c->full_index_path)[9], $mtime,
    "get_latest leaves the marker alone after a recent fetch";
}

sub get_latest_method () {
  local @Latest_paths = qw(
    A/AU/AUTHOR/Alpha-1.0.tar.gz
    B/BR/BRAVO/Bravo-2.0.tar.gz
  );
  my $printed = "A/AU/AUTHOR/Alpha-1.0.tar.gz\nB/BR/BRAVO/Bravo-2.0.tar.gz\n";
  local %Latest_args;
  my $fetched = "C/CH/CHARLIE/Charlie-1.0.tar.gz";
  local @Metacpan_releases = cpan_release($fetched, 5);
  local $Metacpan_total    = 1;

  {
    local $Homedir_dir = cache_dir(undef);
    my $cache = "$Homedir_dir/latest-releases.txt";
    local %Metacpan_args;
    is get_latest_output(Devel::Cover::Collection->new), $printed,
      "get_latest prints one release path per line";
    ok %Metacpan_args, "get_latest fetches a missing cache file";
    ok !exists $Metacpan_args{params}{es_filter},
      "get_latest fetches the full list without a cache file";
    is slurp($cache), "#FORMAT: 1\nCharlie $fetched 5 50\n",
      "get_latest writes the fetched releases to the cache file";
    ok -e "$cache.full", "get_latest writes the full fetch marker";
    is \%Latest_args, { path => $cache }, "get_latest reads the file it wrote";
  }
  {
    local $Homedir_dir = cache_dir(0);
    my $c = Devel::Cover::Collection->new;
    set_age($c->full_index_path, 2 * 24 * 60 * 60);
    local %Metacpan_args;
    is get_latest_output($c), $printed,
      "get_latest prints every path for an old marker";
    ok %Metacpan_args && !exists $Metacpan_args{params}{es_filter},
      "get_latest fetches the full list for an old marker";
    ok $c->full_index_age < 60,
      "get_latest touches an old marker beside a fresh cache file";
  }
  get_latest_recent();

  my $index = cache_dir(0) . "/latest-releases.txt";
  my $c     = Devel::Cover::Collection->new(latest_index => $index);
  local %Metacpan_args;
  is get_latest_output($c), $printed,
    "get_latest prints the latest_index paths";
  is \%Metacpan_args, {}, "get_latest fetches nothing for a latest_index file";
  is slurp($index), "#FORMAT: 1\n",
    "get_latest leaves a latest_index file alone";
  is \%Latest_args, { path => $index },
    "get_latest reads the latest_index file";
}

sub failed_fetch_method () {
  my $scroll = "failed to fetch next scrolled batch\n";
  my $day    = 24 * 60 * 60;
  local @Metacpan_releases = ("die") x 10;
  local $Metacpan_total    = 1;
  my $c                = Devel::Cover::Collection->new(retry_delay => 0);
  my $index_with_alpha = sub {
    $c->write_latest_index({
      released =>
        { Alpha => index_entry("A/AU/AUTHOR/Alpha-1.0.tar.gz", 100) },
      developer => {},
    });
    slurp($c->latest_index_path)
  };

  for my $marker (
    ["two days old" => 2 * $day], ["two hours old" => 2 * 60 * 60]
  ) {
    my ($name, $age) = @$marker;
    local $Homedir_dir = cache_dir(0);
    my $text  = $index_with_alpha->();
    my $mtime = set_age($c->full_index_path, $age);
    my $w     = warnings {
      is dies { $c->get_latest }, $scroll,
        "get_latest dies with the scroll error for a marker $name"
    };

    is @$w, 9, "get_latest retries the fetch for a marker $name";
    is slurp($c->latest_index_path), $text,
      "get_latest leaves the cache file alone for a marker $name";
    is +(stat $c->full_index_path)[9], $mtime,
      "get_latest leaves a marker $name alone after a failed fetch";
  }

  local $Homedir_dir = cache_dir(0);
  my $text = $index_with_alpha->();
  set_age($c->latest_index_path, 2 * $day);
  my $w = warnings {
    is dies { $c->latest_paths }, $scroll,
      "latest_paths dies with the scroll error for an old cache file"
  };
  is @$w, 9, "latest_paths retries the fetch for an old cache file";
  is slurp($c->latest_index_path), $text,
    "latest_paths leaves an old cache file alone after a failed fetch";
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
  my $dir = tempdir(CLEANUP => 1);
  my $c   = Devel::Cover::Collection->new(
    results_dir   => $dir,
    rebuild       => 1,
    rebuild_batch => 10,
  );

  no warnings "redefine";
  my $indexed = 0;
  local *Devel::Cover::Collection::latest_paths = sub {
    $indexed++;
    qw(
      A/AU/AUTHOR/Alpha-1.0.tar.gz
      B/BR/BRAVO/Bravo-2.0.tar.gz
      E/EC/ECHO/Echo-1.0.tar.gz
      E/EC/ECHO/Echo-1.1-TRIAL.tar.gz
    )
  };
  my $called = 0;
  local *Devel::Cover::Collection::cover_modules = sub { $called++; 7 };

  is $c->rebuild_pass, 0, "rebuild_pass returns 0 when queue is empty";
  is $indexed,         0, "rebuild_pass reads no index for an empty queue";

  # Alpha is current, Bravo and Echo are superseded, Charlie is gone
  make_covered($dir, $_) for qw( Alpha-1.0 Bravo-1.0 Charlie-1.0 Echo-0.9 );
  $c->set_failed("Bravo-1.0");

  is $c->rebuild_pass, 7, "rebuild_pass returns the cover_modules count";
  is $called,          1, "cover_modules called once per pass";
  is $indexed,         1, "rebuild_pass reads the index once per pass";
  is [sort $c->modules->@*], [qw(
    A/AU/AUTHOR/Alpha-1.0.tar.gz
    B/BR/BRAVO/Bravo-2.0.tar.gz
    E/EC/ECHO/Echo-1.0.tar.gz
    E/EC/ECHO/Echo-1.1-TRIAL.tar.gz
  )],
    "rebuild_pass builds the current releases of each candidate";
  ok !-e $c->rebuilt_file("Alpha-1.0"),
    "current release is left for cover_modules to mark";
  ok -e $c->rebuilt_file("Bravo-1.0"), "superseded release is marked rebuilt";
  ok -e $c->failed_file("Bravo-1.0"),
    "superseded release keeps its failed marker";
  ok -d "$dir/Bravo-1.0", "superseded release keeps its report";
  ok -e $c->rebuilt_file("Echo-0.9"),
    "release superseded by a TRIAL is marked rebuilt";
  ok -e $c->rebuilt_file("Charlie-1.0"),
    "release no longer on CPAN is marked rebuilt";
  ok -d "$dir/Charlie-1.0", "release no longer on CPAN keeps its report";
}

sub rebuild_pass_nothing_to_build () {
  # Every candidate is gone from CPAN, so there is nothing to feed to
  # cover_modules, but each must still be marked or the batch recurs
  my $dir = tempdir(CLEANUP => 1);
  my $c   = Devel::Cover::Collection->new(
    results_dir   => $dir,
    rebuild       => 1,
    rebuild_batch => 10,
  );

  no warnings "redefine";
  local *Devel::Cover::Collection::latest_paths = sub { () };
  my $called = 0;
  local *Devel::Cover::Collection::cover_modules = sub { $called++; 7 };

  make_covered($dir, "Gone-1.0");
  is $c->rebuild_pass, 0, "rebuild_pass returns 0 with nothing to build";
  is $called,          0, "cover_modules not called with nothing to build";
  ok $c->all_rebuilt, "all_rebuilt true once every candidate is marked";
  is [$c->next_rebuild_batch], [], "batch empty so the rebuild can finish";
}

sub rebuild_pass_mismatched_candidate () {
  skip_all "uses fsys which requires alarm" if $Is_win32;

  # An old release resolves to the current release, which is already
  # covered and rebuilt, so cover_modules skips it silently. The old
  # candidate must still gain a __rebuilt__ marker or the same batch
  # recurs forever and the loop never ends.
  my $dir = tempdir(CLEANUP => 1);
  my $c   = Devel::Cover::Collection->new(
    results_dir   => $dir,
    rebuild       => 1,
    rebuild_batch => 10,
  );

  no warnings "redefine";
  local *Devel::Cover::Collection::latest_paths
    = sub { "S/SI/SINGLE/Single-2.0.tar.gz" };

  make_covered($dir, $_) for qw( Single-1.0 Single-2.0 );
  $c->set_rebuilt("Single-2.0");

  is $c->rebuild_pass, 0, "rebuild_pass runs no builds for skipped candidate";
  ok -e $c->rebuilt_file("Single-1.0"),
    "candidate resolving to a rebuilt distdir is marked rebuilt";
  ok $c->all_rebuilt, "all_rebuilt true once mismatched candidate is marked";
  is [$c->next_rebuild_batch], [], "batch empty so the rebuild can finish";
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
    internal_accessors
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
    sys_timeout
    sys_verbose_output
    bsys_multiline_output
    bsys_stderr_capture
    dc_file
    coverage_class_method
    module_name_version
    write_json
    compress_old_versions
    compress_old_versions_keeps_latest
    compress_old_versions_unreadable_index
    build_dir_id
    build_dir_id_from_cpan
    filter_build_dirs_to_targets
    rebuilt_markers
    unflag_all_rebuilt_method
    known_distdirs_method
    all_rebuilt_method
    next_rebuild_batch_method
    status_tracking_rebuild_mode
    write_status_method
    latest_paths_method
    fetch_latest_releases_method
    release_matches_method
    write_latest_index_method
    read_latest_index_method
    get_latest_method
    failed_fetch_method
    rebuild_pass_method
    rebuild_pass_nothing_to_build
    rebuild_pass_mismatched_candidate
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

# Copyright 2014-2024, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Collection;

use 5.38.0;
use warnings;

# VERSION

use Devel::Cover::DB;
use Devel::Cover::DB::IO::JSON;
use Devel::Cover::Dumper;

use JSON::MaybeXS ();
use Parallel::Iterator "iterate_as_array";
use POSIX "setsid";
use Template;
use Time::HiRes "time";

use Class::XSAccessor ();
use Moo;
use namespace::clean;
use warnings FATAL => "all";  # be explicit since Moo sets this

my %A = (
  ro => [ qw( bin_dir cpancover_dir cpan_dir results_dir dryrun force
    output_file report timeout verbose workers docker local            ) ],
  rwp => [qw( build_dirs local_timeout modules module_file              )],
  rw  => [qw( dir file                                                  )],
);
while (my ($type, $names) = each %A) { has $_ => (is => $type) for @$names }

sub BUILDARGS ($class, %args) { {
  build_dirs    => [],
  cpan_dir      => [ grep -d, glob "~/.cpan ~/.local/share/.cpan" ],
  docker        => "docker",
  dryrun        => 0,
  force         => 0,
  local         => 0,
  local_timeout => 0,
  modules       => [],
  output_file   => "index.html",
  report        => "html_basic",
  timeout       => 1800,  # half an hour
  verbose       => 0,
  workers       => 0,
  %args,
} }

sub get_timeout ($self) { $self->local_timeout || $self->timeout || 30 * 60 }

# display $non_buffered characters, then buffer
sub _sys ($self, $non_buffered, @command) {
  # system @command; return ".";
  my ($output1, $output2) = ("", "");
  $output1 = "dc -> @command\n" if $self->verbose;
  my $timeout = $self->get_timeout;
  my $max     = 4e4;
  # say "Setting alarm for $timeout seconds";
  my $ok = 0;
  my $pid;
  eval {
    open STDIN, "<", "/dev/null" or die "Can't read /dev/null: $!";
    $pid = open my $fh, "-|" // die "Can't fork: $!";
    if ($pid) {
      my $printed = 0;
      local $SIG{ALRM} = sub { die "alarm\n" };
      alarm $timeout;
      while (<$fh>) {
        # print "got: $_";
        # say "printed $printed of $non_buffered";
        if ($printed < $non_buffered) {
          print;
          if (($printed += length) >= $non_buffered) {
            say "Devel::Cover: buffering ...";
          }
        } elsif (length $output2) {
          $output2 = substr $output2 . $_, $max * -.1, $max * .1;
        } else {
          $output1 .= $_;
          if (length $output1 > $max * .9) {
            $output1 = substr $output1, 0, $max * .9;
            $output2 = "\n";
          }
        }
      }
      alarm 0;
      if (close $fh) {
        $ok = 1;
      } else {
        warn "Error running @command\n";
      }
    } else {
      setsid() != -1 or die "Can't start a new session: $!";
      open STDERR, ">&", STDOUT or die "Can't dup stdout: $!";
      exec @command or die "Can't exec @command: $!";
    }
  };
  if ($@) {
    $ok = 0;
    die "$@" unless $@ eq "alarm\n";  # propagate unexpected errs
    warn "Timed out after $timeout seconds!\n";
    my $pgrp = getpgrp $pid;
    my $n    = kill "-KILL", $pgrp;
    warn "killed $n processes";
  }
  $ok ? length $output2 ? "$output1\n...\n$output2" : $output1 : undef
}

sub sys   ($s, @a) { $s->_sys(4e4, @a) // "" }
sub bsys  ($s, @a) { $s->_sys(0,   @a) // "" }
sub fsys  ($s, @a) { $s->_sys(4e4, @a) // die "Can't run @a" }
sub fbsys ($s, @a) { $s->_sys(0,   @a) // die "Can't run @a" }

sub add_modules     ($self, @o)    { push $self->modules->@*, @o }
sub set_modules     ($self, @o)    { $self->modules->@* = @o }
sub set_module_file ($self, $file) { $self->set_module_file($file) }

sub process_module_file ($self) {
  my $file = $self->module_file;
  return unless defined $file && length $file;
  open my $fh, "<", $file or die "Can't open $file: $!";
  my $modules = do { local $/; <$fh> };
  close $fh or die "Can't close $file: $!";
  my @modules = grep /\S/, grep !/^ *#/, split /\n/, $modules;
  $self->add_modules(@modules);
}

sub build_modules ($self) {
  my @command = qw( cpan -i -T );
  push @command, "-f" if $self->force;
  # my @command = qw( cpan );
  # $ENV{CPAN_OPTS} = "-i -T";
  # $ENV{CPAN_OPTS} .= " -f" if $self->force;
  # $self->_set_local_timeout(300);
  my %m;
  for my $module (sort grep !$m{$_}++, $self->modules->@*) {
    say "Building $module";
    my $output = $self->fsys(@command, $module);
    say $output;
  }
  $self->_set_local_timeout(0);
}

sub add_build_dirs ($self) {
  # say "add_build_dirs"; say for @{$self->build_dirs};
  # say && system "ls -al $_" for "/remote_staging",
  # map "$_/build", @{$self->cpan_dir};
  my $exists = sub {
    # say "exists [$_]";
    my $dir   = "/remote_staging/" . (s|.*/||r =~ s/-\d+$/*/r);
    my @files = glob $dir;
    # say "checking [$dir] -> [@files]";
    @files
  };
  push $self->build_dirs->@*, grep { !$exists->() } grep -d,
    map glob("$_/build/*"), $self->cpan_dir->@*;
  # say "add_build_dirs:"; say for @{$self->build_dirs};
}

sub run ($self, $build_dir) {

  my ($module)    = $build_dir =~ m|.*/([^/]+?)(?:-\d+)$| or return;
  my $db          = "$build_dir/cover_db";
  my $line        = "=" x 80;
  my $output      = "**** Checking coverage of $module ****\n";
  my $results_dir = $self->results_dir // die "No results dir";

  $output      .= $self->fsys("mkdir", "-p", $results_dir);
  $results_dir .= "/$module";

  chdir $build_dir or die "Can't chdir $build_dir: $!\n";
  say "Checking coverage of $module";

  if (-d $db || -d "$build_dir/structure" || -d $results_dir) {
    $output .= "Already analysed\n";
    unless ($self->force) {
      say "\n$line\n$output$line\n";
      return;
    }
  }

  $output .= "Testing $module in $build_dir\n";
  # say "\n$line\n$output$line\n"; return;

  # $output .= $self->sys($^X, "-V");
  # $output .= $self->sys("pwd");
  my @cmd;
  if ($self->local) {
    $ENV{DEVEL_COVER_OPTIONS}   = "-ignore,/usr/local/lib/perl5";
    $ENV{DEVEL_COVER_TEST_OPTS} = "-Mblib=" . $self->bin_dir;
    @cmd = ($^X, $ENV{DEVEL_COVER_TEST_OPTS}, $self->bin_dir . "/cover");
  } else {
    @cmd = ($^X, $self->bin_dir . "/cover");
  }
  $output
    .= $self->fbsys(@cmd, "--test", "--report", $self->report, "--outputfile",
      $self->output_file);
  $output .= $self->fsys(@cmd, "-report", "json", "-nosummary");

  # TODO - option to merge DB with existing one
  # TODO - portability
  $output .= $self->fsys("rm", "-rf", $results_dir);
  $output .= $self->fsys("mv", $db,   $results_dir);
  $output .= $self->fsys("rm", "-rf", $db);

  say "\n$line\n$output$line\n";
}

sub run_all ($self) {
  my $results_dir = $self->results_dir // die "No results dir";
  $self->fsys("mkdir", "-p", $results_dir);

  my @res = iterate_as_array(
    { workers => $self->workers },
    sub {
      my (undef, $dir) = @_;
      eval { $self->run($dir) };
      warn "\n\n\n[$dir]: $@\n\n\n" if $@;
    },
    $self->build_dirs
  );
  # print Dumper \@res;
}

sub write_json ($self, $vars) {
  # print Dumper $vars;
  my $results = {};
  for my $module (keys $vars->{vals}->%*) {
    my $m   = $vars->{vals}{$module};
    my $mod = $m->{module};
    my ($name, $version) = ($mod->{module} // $module) =~ /(.+)-(\d+\.\d+)$/;
    $name    = $mod->{name}    if defined $mod->{name};
    $version = $mod->{version} if defined $mod->{version};
    if (defined $name && defined $version) {
      $results->{$name}{$version}{coverage}{total} = {
        map { $_ => $m->{$_}{pc} } grep $m->{$_}{pc} ne 'n/a',
        grep !/link|log|module/,
        keys %$m,
      };
    } else {
      print "Cannot process $module: ", Dumper $m if $self->verbose;
    }
  }
  # print Dumper $vars, $results;

  my $io   = Devel::Cover::DB::IO::JSON->new(options => "pretty");
  my $file = $self->results_dir . "/cpancover.json";
  $io->write($results, $file);
  say "Wrote json output to $file";
}

sub class {
  my ($pc) = @_;
      $pc eq "n/a" ? "na"
    : $pc < 75     ? "c0"
    : $pc < 90     ? "c1"
    : $pc < 100    ? "c2"
    : "c3"
}

sub write_summary($self, $vars) {
  my $d = $self->dir;
  my $f = $self->file;

  $self->write_stylesheet;
  my $template = Template->new({
    LOAD_TEMPLATES =>
      [ Devel::Cover::Collection::Template::Provider->new({}) ]
  });
  $template->process("summary", $vars, $f) or die $template->error;
  for my $start (sort keys $vars->{modules}->%*) {
    $vars->{module_start} = $start;
    my $dist = "$d/dist/$start.html";
    $template->process("module_by_start", $vars, $dist) or die $template->error;
  }

  my $about_f = "$d/about.html";
  say "\nWriting about page to $about_f ...";

  $template->process("about", { subdir => "latest/" }, $about_f)
    or die $template->error;

  # print Dumper $vars;
  $self->write_json($vars);

  say "Wrote collection output to $f";
}

sub generate_html ($self) {
  my $d = $self->results_dir;
  chdir $d or die "Can't chdir $d: $!\n";
  $self->dir($d);

  my $f = "$d/index.html";
  $self->file($f);
  say "\n\nWriting collection output to $f ...";

  my $vars = {
    title   => "Coverage report",
    modules => {},
    vals    => {},
    subdir  => "latest/",
    headers =>
      [ grep !/path|time/, @Devel::Cover::DB::Criteria_short, "total" ],
    criteria => [ grep !/path|time/, @Devel::Cover::DB::Criteria, "total" ],
  };

  opendir my $dh, $d or die "Can't opendir $d: $!";
  my @modules = sort grep !/^\./, readdir $dh;
  closedir $dh or die "Can't closedir $d: $!";

  my $n = 0;
  for my $module (@modules) {
    my $cover = "$d/$module/cover.json";
    next                 unless -e $cover;
    say "Adding $module" if $self->verbose;

    my $io   = Devel::Cover::DB::IO::JSON->new;
    my $json = $io->read($cover);

    my $mod = {
      module => $module,
      map { $_ => $json->{runs}[0]{$_} } qw( name version dir ),
    };
    unless (defined $mod->{name} && defined $mod->{version}) {
      my ($name, $version) = ($mod->{module} // $module) =~ /(.+)-(\d+\.\d+)$/;
      $mod->{name}    //= $name;
      $mod->{version} //= $version;
    }
    my $start = uc substr $module, 0, 1;
    push @{ $vars->{modules}{$start} }, $mod;

    my $m = $vars->{vals}{$module} = {};
    $m->{module} = $mod;
    $m->{link} = "/$module/index.html" if $json->{summary}{Total}{total}{total};

    for my $criterion ($vars->{criteria}->%*) {
      my $summary = $json->{summary}{Total}{$criterion};
      # print "summary:", Dumper $summary;
      my $pc = $summary->{percentage};
      $pc                     = defined $pc ? sprintf "%.2f", $pc : "n/a";
      $m->{$criterion}{pc}    = $pc;
      $m->{$criterion}{class} = class($pc);
      $m->{$criterion}{details}
        = ($summary->{covered} || 0) . " / " . ($summary->{total} || 0);
    }

    print "." if !($n++ % 1000) && !$self->verbose;
  }

  $n = 0;
  for my $file (@modules) {
    # say "looking at [$file]";
    my ($module) = $file =~ /^ \w - \w\w - \w+ - (.*)
                                 \. (?: zip | tgz | (?: tar \. (?: gz | bz2 )))
                                 -- \d{10,11} \. \d{6} \. out \. gz $/x
      or next;
    # say "found at [$module]";
    $vars->{vals}{$module}{log} = $file;
    print "-" if !($n++ % 1000) && !$self->verbose;
  }
  say "";

  # print "vars ", Dumper $vars;
  $self->write_summary($vars);
}

sub compress_old_versions ($self, $versions) {
  my $dir = $self->results_dir;
  opendir my $fh, $dir or die "Can't opendir $dir: $!";
  my @dirs = sort grep -d, map "$dir/$_", readdir $fh;
  closedir $fh or die "Can't closedir $dir: $!";

  my %modules;
  for my $dir (@dirs) {
    my $file = "$dir/cover.json";
    my $json = JSON::MaybeXS->new(utf8 => 1, allow_blessed => 1);
    open my $fh, "<", $file or next;
    # say "file: $file";
    my $data
      = do { local $/; eval { $json->decode(<$fh>) } }
      or next;
    next if $@;
    close $fh or next;
    my ($name) = $dir =~ /.+\/(.+)/;
    $name =~ s/-[^-]+$//;
    my @runs = grep { ($_->{name} // "") eq $name } $data->{runs}->@*;
    # say "$name " . @runs;
    my $run     = $runs[0]                   // next;
    my $version = $run->{version} =~ s/_//gr // next;
    my $v       = eval { version->parse($version)->numify };
    if ($@ || !$v) {
      $v = $version;
      $v =~ s/[^0-9.]//g;
      my @parts = split /\./, $v;
      if (@parts > 2) {
        $v = shift(@parts) . "." . join "", @parts;
      }
    }
    $v ||= 0;
    push $modules{$name}->@*, { dir => $dir, version => $v };
  }

  for my $name (sort keys %modules) {
    # print Dumper $modules{$name};
    my @o = sort { $b->{version} <=> $a->{version} } $modules{$name}->@*;
    shift @o for 1 .. $versions;
    for my $v (@o) {

      my ($d, $s) = $v->{dir} =~ /(.+)\/(.+)/;
      my $archive = "$v->{dir}.tar.xz";
      my @cmd1    = ($self->dc_file, "-r", $d, "cpancover-uncompress-dir", $s);
      my @cmd2    = ("bash", "-c",  "tar cf - -C $d $s | xz -z > $archive");
      my @cmd3    = ("rm",   "-rf", $v->{dir});

      if ($self->dryrun) {
        say for "compressing $s", "@cmd1", "@cmd2", "@cmd3";
      } else {
        say "compressing $s";
        eval { $self->fsys(@$_) for \@cmd1, \@cmd2, \@cmd3; };
        say $@ if $@;
      }
    }
  }
}

sub local_build ($self) {
  $self->process_module_file;
  $self->build_modules;
  $self->add_build_dirs;
  $self->run_all;
}

sub failed_dir ($self) {
  my $dir = $self->results_dir . "/__failed__";
  -d $dir or mkdir $dir or die "Can't mkdir $dir: $!";
  $dir
}

sub covered_dir ($self, $dir) { $self->results_dir . "/$dir" }
sub failed_file ($self, $dir) { $self->failed_dir . "/$dir" }
sub is_covered  ($self, $dir) { -d $self->covered_dir($dir) }
sub is_failed   ($self, $dir) { -e $self->failed_file($dir) }
sub set_covered ($self, $dir) { unlink $self->failed_file($dir) }

sub set_failed ($self, $dir) {
  my $ff = $self->failed_file($dir);
  open my $fh, ">", $ff or return warn "Can't open $ff: $!";
  print $fh scalar localtime;
  close $fh or warn "Can't close $ff: $!";
}

sub dc_file ($self) {
  my $dir = "";
  $dir = "/dc/" if $self->local && -d "/dc";
  "${dir}utils/dc"
}

sub cover_modules ($self) {
  $self->process_module_file;
  # say "modules: ", Dumper $self->modules;

  my @cmd = $self->dc_file;
  push @cmd, "--local" if $self->local;
  my @command = (@cmd, "cpancover-docker-module");
  $self->_set_local_timeout(0);
  my @res = iterate_as_array(
    { workers => $self->workers },
    sub {
      # say "mod ", Dumper \@_;
      my (undef, $module) = @_;
      my $dir
        = $module =~ s|.*/||r =~ s/\.(?:zip|tgz|(?:tar\.(?:gz|bz2)))$//r;
      if ($self->is_covered($dir)) {
        $self->set_covered($dir);
        say "$module already covered" if $self->verbose;
        return                        unless $self->force;
      } elsif ($self->is_failed($dir)) {
        say "$module already failed" if $self->verbose;
        return                       unless $self->force;
      }

      my $timeout = $self->get_timeout;
      # say "Setting alarm for $timeout seconds";
      my $name = sprintf("%s-%18.6f", $module, time) =~ tr/a-zA-Z0-9_./-/cr;
      say "$dir -> $name";
      eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm $timeout;
        say "running: @command $module $name" if $self->verbose;
        system @command, $module, $name;
        alarm 0;
      };
      if ($@) {
        die "$@" unless $@ eq "alarm\n";  # unexpected errors
        say "Timed out after $timeout seconds!";
        $self->sys($self->docker, "kill", $name);
        say "Killed docker container $name";
      }

      if ($self->is_covered($dir)) {
        $self->set_covered($dir);
        say "$dir done";
      } else {
        $self->set_failed($dir);
        say "$dir failed";
      }
    },
    do { my %m; [ sort grep !$m{$_}++, @{ $self->modules } ] }
  );
  $self->_set_local_timeout(0);
}

sub get_latest ($self) {
  require CPAN::Releases::Latest;

  my $latest   = CPAN::Releases::Latest->new(max_age => 0);  # no caching
  my $iterator = $latest->release_iterator;

  while (my $release = $iterator->next_release) {
    say $release->path;
    # Debugging code:
    # printf "%s path=%s  time=%d  size=%d\n",
    # $release->distname,
    # $release->path,
    # $release->timestamp,
    # $release->size;
  }
}

sub write_stylesheet ($self) {
  my $css = $self->results_dir . "/collection.css";
  open my $fh, ">", $css or die "Can't open $css: $!\n";
  print $fh <<EOF;
/* Stylesheet for Devel::Cover collection reports */

/* You may modify this file to alter the appearance of your coverage
 * reports. If you do, you should probably flag it read-only to prevent
 * future runs from overwriting it.
 */

/* Note: default values use the color-safe web palette. */

body {
  font-family: sans-serif;
}

h1 {
  text-align : center;
  background-color: #cc99ff;
  border: solid 1px #999999;
  padding: 0.2em;
  -moz-border-radius: 10px;
}

a {
  color: #000000;
}
a:visited {
  color: #333333;
}

table {
  border-spacing: 0px;
}
tr {
  text-align : center;
  vertical-align: top;
}
th,.h,.hh {
  background-color: #cccccc;
  border: solid 1px #333333;
  padding: 0em 0.2em;
  -moz-border-radius: 4px;
}
td {
  border: solid 1px #cccccc;
  border-top: none;
  border-left: none;
  -moz-border-radius: 4px;
}
.hblank {
  height: 0.5em;
}
.dblank {
  border: none;
}

/* source code */
pre,.s {
  text-align: left;
  font-family: monospace;
  white-space: pre;
  padding: 0.2em 0.5em 0em 0.5em;
}

/* Classes for color-coding coverage information:
 *   c0  : path not covered or coverage < 75%
 *   c1  : coverage >= 75%
 *   c2  : coverage >= 90%
 *   c3  : path covered or coverage = 100%
 */
.c0 {
  background-color: #ff9999;
  border: solid 1px #cc0000;
}
.c1 {
  background-color: #ffcc99;
  border: solid 1px #ff9933;
}
.c2 {
  background-color: #ffff99;
  border: solid 1px #cccc66;
}
.c3 {
  background-color: #99ff99;
  border: solid 1px #009900;
}
EOF

  close $fh or die "Can't close $css: $!\n";
}

package Devel::Cover::Collection::Template::Provider;

use strict;
use warnings;

# VERSION

use base "Template::Provider";

my %Templates;

sub fetch ($self, $name) {
  # print "Looking for <$name>\n";
  $self->SUPER::fetch(exists $Templates{$name} ? \$Templates{$name} : $name)
}

$Templates{colours} = <<'EOT';
[%
  colours = {
    default => "#ffffad",
    text    => "#000000",
    number  => "#ffffc0",
    error   => "#ff0000",
    ok      => "#00ff00",
  }
%]

[% MACRO bg BLOCK -%]
bgcolor="[% colours.$colour %]"
[%- END %]
EOT

$Templates{html} = <<'EOT';
<!DOCTYPE html
  PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<!--
This file was generated by Devel::Cover Version $VERSION
Devel::Cover is copyright 2001-2024, Paul Johnson (paul\@pjcj.net)
Devel::Cover is free. It is licensed under the same terms as Perl itself.
The latest version of Devel::Cover should be available from my homepage:
http://www.pjcj.net
-->
[% PROCESS colours %]
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8"></meta>
  <meta http-equiv="Content-Language" content="en-us"></meta>
  <link rel="stylesheet" type="text/css" href="/[% subdir %]collection.css"></link>
  <title> [% title %] </title>
</head>
<body>
  [% content %]
  <hr/>
  <p>
  Coverage information from <a href="https://metacpan.org/module/Devel::Cover">
    Devel::Cover
  </a> by <a href="http://pjcj.net">Paul Johnson</a>.

  <br/>

  Please report problems with this site to the
  <a href="https://github.com/pjcj/Devel--Cover/issues">issue tracker</a>.</p>

  <p><a href="http://cpancover.com/latest/about.html">About</a> the project.</p>

  <p>This server generously donated by
  <a href="http://www.bytemark.co.uk/r/cpancover">
    <img src="http://www.bytemark.co.uk/images/subpages/spreadtheword/bytemark_logo_179_x_14.png" alt="bytemark"/>
  </a>
  </p>
</body>
</html>
EOT

$Templates{summary} = <<'EOT';
[% WRAPPER html %]

<h1> CPANCover </h1>

<h2> Distributions </h2>

<p>Search for distributions by first character:</p>

[% FOREACH start = modules.keys.sort %]
  <a href="dist/[%- start -%].html">[% start %]</a>
[% END %]

<h2> Core coverage </h2>

<a href="http://cpancover.com/blead/latest/coverage.html">Perl core coverage</a>
(under development)

[% END %]
EOT

$Templates{about} = <<'EOT';
[% WRAPPER html %]

<h1> CPANCover </h1>

<h2> About </h2>

<p>CPANCover is a project to provide code coverage information for <a
href="https://metacpan.org"> CPAN</a> modules.  When a new module, or an update to an
existing module, is uploaded to CPAN it will automatically be downloaded by
CPANCover.  CPANCover will run the module's tests and measure the code coverage
provided by the tests.  This information is then made available as HTML pages
and JSON data.</p>

<p>The coverage data is generated by <a
href="https://metacpan.org/release/Devel-Cover">Devel::Cover</a>.

<p>The source code is available at the
  <a href="https://github.com/pjcj/Devel--Cover">GitHub repository</a>.
  Contributions are also accepted for several
  <a href="http://pjcj.net/devel-cover/projects.html">open projects</a>.
</p>

[% END %]
EOT

$Templates{module_by_start} = <<'EOT';
[% WRAPPER html %]

<h1> [% title %] - [% module_start %] </h1>

<table>

  [% IF modules.$module_start %]
    <tr align="right" valign="middle">
      <th class="header" align="left" style='white-space: nowrap;'> Module </th>
      <th class="header"> Version </th>
      <th class="header"> Log </th>
      [% FOREACH header = headers %]
        <th class="header"> [% header %] </th>
      [% END %]
    </tr>
  [% END %]

  [% FOREACH module = modules.$module_start %]
    [% m = module.module %]
    <tr align="right" valign="middle">
      <td align="left">
        [% IF vals.$m.link %]
          <a href="/[% subdir %][%- vals.$m.link -%]">
            [% module.name || module.module %]
          </a>
        [% ELSE %]
          [% module.name || module.module %]
        [% END %]
      </td>
      <td> [% module.version %] </td>
      <td> <a href="/[% subdir %][% vals.$m.log %]"> &para; </a> </td>
      [% FOREACH criterion = criteria %]
        <td class="[%- vals.$m.$criterion.class -%]"
          title="[%- vals.$m.$criterion.details -%]">
          [% vals.$m.$criterion.pc %]
        </td>
      [% END %]
    </tr>
  [% END %]

</table>

<br/>

[% END %]
EOT

"
We have normality, I repeat we have normality.
Anything you still can’t cope with is therefore your own problem.
"

__END__

=head1 NAME

Devel::Cover::Collection - Code coverage for a collection of modules

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 OPTIONS

=head1 ENVIRONMENT

=head1 BUGS

Almost certainly.

=head1 LICENCE

Copyright 2014-2024, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available on CPAN and from my
homepage: http://www.pjcj.net/.

=cut

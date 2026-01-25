# Copyright 2014-2025, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Collection;

use 5.42.0;
use warnings;

# VERSION

use Devel::Cover::DB           ();
use Devel::Cover::DB::IO::JSON ();
use Devel::Cover::Dumper       qw( Dumper );
use Devel::Cover::Web          qw( write_file );

use JSON::MaybeXS      ();
use Parallel::Iterator qw( iterate_as_array );
use POSIX              qw( setsid );
use Template           ();
use Time::HiRes        qw( alarm time );

use feature "class";

no warnings "experimental::class";

class Devel::Cover::Collection {
  # ro attributes
  field $bin_dir       : param : reader = undef;
  field $cpancover_dir : param : reader = undef;
  field $cpan_dir      : param : reader = undef;
  field $results_dir   : param : reader = undef;
  field $dryrun        : param : reader = undef;
  field $env           : param : reader = undef;
  field $force         : param : reader = undef;
  field $output_file   : param : reader = undef;
  field $report        : param : reader = undef;
  field $timeout       : param : reader = undef;
  field $verbose       : param : reader = undef;
  field $workers       : param : reader = undef;
  field $docker        : param : reader = undef;
  field $local         : param : reader = undef;

  # rwp attributes (reader + private setter)
  field $build_dirs  : param : reader = undef;
  field $modules     : param : reader = undef;
  field $module_file : param : reader = undef;

  # rw attributes (custom accessors for Moo compatibility)
  field $dir  : param = undef;
  field $file : param = undef;

  ADJUST {
    # Apply defaults (equivalent to BUILDARGS)
    $build_dirs  //= [];
    $cpan_dir    //= [ grep -d, glob "~/.cpan ~/.local/share/.cpan" ];
    $docker      //= "docker";
    $dryrun      //= 0;
    $env         //= "prod";
    $force       //= 0;
    $local       //= 0;
    $modules     //= [];
    $output_file //= "index.html";
    $report      //= "html_basic";
    $timeout     //= 30 * 60;  # half an hour
    $verbose     //= 0;
    $workers     //= 0;
  }

  # rwp private setters
  method _set_build_dirs  ($val) { $build_dirs  = $val }
  method _set_modules     ($val) { $modules     = $val }
  method _set_module_file ($val) { $module_file = $val }

  # rw accessors (Moo-compatible: reader acts as writer when called with arg)
  method dir  ($new = undef) { $dir  = $new if defined $new; $dir }
  method file ($new = undef) { $file = $new if defined $new; $file }

  # display $non_buffered characters, then buffer
  method _sys ($non_buffered, @command) {
    # system @command; return ".";
    my ($output1, $output2) = ("", "");
    $output1 = "dc -> @command\n" if $verbose;
    my $max = 4e4;
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
            say "Devel::Cover: buffering ..."
              if ($printed += length) >= $non_buffered;
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

  method sys   (@a) { $self->_sys(4e4, @a) // "" }
  method bsys  (@a) { $self->_sys(0,   @a) // "" }
  method fsys  (@a) { $self->_sys(4e4, @a) // die "Can't run @a" }
  method fbsys (@a) { $self->_sys(0,   @a) // die "Can't run @a" }

  method add_modules     (@o) { push $modules->@*, @o }
  method set_modules     (@o) { $modules->@* = @o }
  method set_module_file ($f) { $self->_set_module_file($f) }

  method process_module_file {
    my $f = $module_file;
    return unless defined $f && length $f;
    open my $fh, "<", $f or die "Can't open $f: $!";
    my $m = do { local $/; <$fh> };
    close $fh or die "Can't close $f: $!";
    my @m = grep /\S/, grep !/^ *#/, split /\n/, $m;
    $self->add_modules(@m);
  }

  method build_modules {
    my @command = qw( cpan -Ti );
    push @command, "-f" if $force;
    my %m;
    for my $module (sort grep !$m{$_}++, $modules->@*) {
      say "Building $module";
      my $output = $self->fsys(@command, $module);
      say $output;
    }
  }

  method add_build_dirs {
    my $exists = sub {
      my $d     = "/remote_staging/" . (s|.*/||r =~ s/-\d+$/*/r);
      my @files = glob $d;
      @files
    };
    push $build_dirs->@*, grep { !$exists->() } grep -d,
      map glob("$_/build/*"), $cpan_dir->@*;
  }

  method made_res_dir ($sub_dir = undef) {
    my $d = $results_dir // die "No results dir";
    $d .= "/$sub_dir" if defined $sub_dir;
    my $output = $self->fsys("mkdir", "-p", $d);
    $d, $output
  }

  method run ($build_dir) {
    chdir $build_dir or die "Can't chdir $build_dir: $!\n";
    my ($module) = $build_dir =~ m|.*/([^/]+?)(?:-\d+)$| or return;
    say "Checking coverage of $module";

    my $db   = "$build_dir/cover_db";
    my $line = "=" x 80;
    my ($res_dir, $out) = $self->made_res_dir;
    my $rdir   = "$res_dir/$module";
    my $output = "**** Checking coverage of $module ****\n$out";

    if (-d $db || -d "$build_dir/structure" || -d $rdir) {
      $output .= "Already analysed\n";
      unless ($force) {
        say "\n$line\n$output$line\n";
        return;
      }
    }

    $output .= "Testing $module in $build_dir\n";

    my @cmd;
    if ($local) {
      $ENV{DEVEL_COVER_OPTIONS}   = "-ignore,/usr/local/lib/perl5";
      $ENV{DEVEL_COVER_TEST_OPTS} = "-Mblib=" . $bin_dir . "/..";
      @cmd = ($^X, $ENV{DEVEL_COVER_TEST_OPTS}, $bin_dir . "/cover");
    } else {
      @cmd = ($^X, $bin_dir . "/cover");
    }
    $output .= $self->fbsys(@cmd, "--test", "--report", $report, "--outputfile",
      $output_file);
    $output .= $self->fsys(@cmd, "-report", "json", "-nosummary");

    # TODO - option to merge DB with existing one
    # TODO - portability
    $output .= $self->fsys("rm", "-rf", $rdir);
    $output .= `rm -f $db/structure/*.lock`;
    $output .= $self->fsys("mv", $db,   $rdir);
    $output .= $self->fsys("rm", "-rf", $db);

    say "\n$line\n$output$line\n";
  }

  method run_all {
    my @res = iterate_as_array(
      { workers => $workers },
      sub {
        my (undef, $d) = @_;
        eval { $self->run($d) };
        warn "\n\n\n[$d]: $@\n\n\n" if $@;
      },
      $build_dirs
    );
  }

  method write_json ($vars) {
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
          map { $_ => $m->{$_}{pc} } grep $m->{$_}{pc} ne "n/a",
          grep !/link|log|module/,
          keys %$m,
        };
      } else {
        print "Cannot process $module: ", Dumper $m if $verbose;
      }
    }
    # print Dumper $vars, $results;

    my $io     = Devel::Cover::DB::IO::JSON->new(options => "pretty");
    my ($rdir) = $self->made_res_dir;
    my $f      = "$rdir/cpancover.json";
    $io->write($results, $f);
    say "Wrote json output to $f";
  }

  method write_summary ($vars) {
    my $d = $self->dir;
    my $f = $self->file;

    write_file(($self->made_res_dir)[0], "collection.css");
    my $template = Template->new({
      LOAD_TEMPLATES =>
        [ Devel::Cover::Collection::Template::Provider->new({}) ]
    });
    $template->process("summary", $vars, $f) or die $template->error;
    for my $start (sort keys $vars->{modules}->%*) {
      $vars->{module_start} = $start;
      my $dist = "$d/dist/$start.html";
      $template->process("module_by_start", $vars, $dist)
        or die $template->error;
    }

    my $about_f = "$d/about.html";
    say "\nWriting about page to $about_f ...";

    $template->process("about", { subdir => "latest/" }, $about_f)
      or die $template->error;

    # print Dumper $vars;
    $self->write_json($vars);

    say "Wrote collection output to $f";
  }

  method generate_html {
    my ($d) = $self->made_res_dir;
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
    my @mods = sort grep !/^\./, readdir $dh;
    closedir $dh or die "Can't closedir $d: $!";

    my $n = 0;
    for my $module (@mods) {
      my $cover = "$d/$module/cover.json";
      next unless -e $cover;
      say "Adding $module" if $verbose;

      my $io   = Devel::Cover::DB::IO::JSON->new;
      my $json = $io->read($cover);

      my $mod = {
        module => $module,
        map { $_ => $json->{runs}[0]{$_} } qw( name version dir ),
      };
      unless (defined $mod->{name} && defined $mod->{version}) {
        my ($name, $version)
          = ($mod->{module} // $module) =~ /(.+)-(\d+\.\d+)$/;
        $mod->{name}    //= $name;
        $mod->{version} //= $version;
      }
      my $start = uc substr $module, 0, 1;
      push $vars->{modules}{$start}->@*, $mod;

      my $m = $vars->{vals}{$module} = {};
      $m->{module} = $mod;
      $m->{link}   = "/$module/index.html"
        if $json->{summary}{Total}{total}{total};

      for my $criterion ($vars->{criteria}->@*) {
        my $summary = $json->{summary}{Total}{$criterion};
        # print "summary:", Dumper $summary;
        my $pc = $summary->{percentage};
        $pc                     = defined $pc ? sprintf "%.2f", $pc : "n/a";
        $m->{$criterion}{pc}    = $pc;
        $m->{$criterion}{class} = &class($pc);  ## no critic (AmpersandSigils)
        $m->{$criterion}{details}
          = ($summary->{covered} || 0) . " / " . ($summary->{total} || 0);
      }

      print "." if !($n++ % 1000) && !$verbose;
    }

    $n = 0;
    for my $f (@mods) {
      # say "looking at [$f]";
      my ($module) = $f =~ /^ \w - \w\w - \w+ - (.*)
                                  \. (?: zip | tgz | (?: tar \. (?: gz | bz2 )))
                                  -- \d{10,11} \. \d{6} \. out \. gz $/x
        or next;
      # say "found at [$module]";
      $vars->{vals}{$module}{log} = $f;
      print "-" if !($n++ % 1000) && !$verbose;
    }
    say "";

    # print "vars ", Dumper $vars;
    $self->write_summary($vars);
  }

  method compress_old_versions ($versions) {
    my ($d) = $self->made_res_dir;
    opendir my $fh, $d or die "Can't opendir $d: $!";
    my @dirs = sort grep -d, map "$d/$_", readdir $fh;
    closedir $fh or die "Can't closedir $d: $!";

    my %mods;
    for my $entry (@dirs) {
      my $f    = "$entry/cover.json";
      my $json = JSON::MaybeXS->new(utf8 => 1, allow_blessed => 1);
      open my $fh, "<", $f or next;
      # say "file: $f";
      my $data
        = do { local $/; eval { $json->decode(<$fh>) } }
        or next;
      next if $@;
      close $fh or next;
      my ($name) = $entry =~ /.+\/(.+)/;
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
      push $mods{$name}->@*, { dir => $entry, version => $v };
    }

    for my $name (sort keys %mods) {
      # print Dumper $mods{$name};
      my @o = sort { $b->{version} <=> $a->{version} } $mods{$name}->@*;
      shift @o for 1 .. $versions;
      for my $v (@o) {

        my ($parent, $s) = $v->{dir} =~ /(.+)\/(.+)/;
        my $archive = "$v->{dir}.tar.xz";
        my @cmd1
          = ($self->dc_file, "-r", $parent, "cpancover-uncompress-dir", $s);
        my @cmd2 = ("bash", "-c",  "tar cf - -C $parent $s | xz -z > $archive");
        my @cmd3 = ("rm",   "-rf", $v->{dir});

        if ($dryrun) {
          say for "compressing $s", "@cmd1", "@cmd2", "@cmd3";
        } else {
          say "compressing $s";
          eval { $self->fsys(@$_) for \@cmd1, \@cmd2, \@cmd3; };
          say $@ if $@;
        }
      }
    }
  }

  method local_build {
    $self->process_module_file;
    $self->build_modules;
    $self->add_build_dirs;
    $self->run_all;
  }

  method failed_dir { ($self->made_res_dir("__failed__"))[0] }
  method covered_dir ($d) { $results_dir . "/$d" }
  method failed_file ($d) { $self->failed_dir . "/$d" }
  method is_covered  ($d) { -d $self->covered_dir($d) }
  method is_failed   ($d) { -e $self->failed_file($d) }
  method set_covered ($d) { unlink $self->failed_file($d) }

  method set_failed ($d) {
    my $ff = $self->failed_file($d);
    open my $fh, ">", $ff or return warn "Can't open $ff: $!";
    print $fh scalar localtime;
    close $fh or warn "Can't close $ff: $!";
  }

  method dc_file {
    my $d = "";
    $d = "/dc/" if $local && -d "/dc";
    "${d}utils/dc"
  }

  method cover_modules {
    $self->process_module_file;
    # say "modules: ", Dumper $modules;

    my @cmd = ($self->dc_file, "--env", $env);
    push @cmd, "--verbose" if $verbose;
    my @command = (@cmd, "cpancover-docker-module");
    my @res     = iterate_as_array(
      { workers => $workers },
      sub {
        # say "mod ", Dumper \@_;
        my (undef, $module) = @_;
        my $d
          = $module =~ s|.*/||r =~ s/\.(?:zip|tgz|(?:tar\.(?:gz|bz2)))$//r;
        if ($self->is_covered($d)) {
          $self->set_covered($d);
          say "$module already covered" if $verbose;
          return unless $force;
        } elsif ($self->is_failed($d)) {
          say "$module already failed" if $verbose;
          return unless $force;
        }

        my $to = $timeout;
        # say "Setting alarm for $to seconds";
        my $name = sprintf("%s-%18.6f", $module, time) =~ tr/a-zA-Z0-9_./-/cr;
        say "$d -> $name";
        eval {
          local $SIG{ALRM} = sub { die "alarm\n" };
          alarm $to;
          say "running: @command $module $name" if $verbose;
          system @command, $module, $name;
          alarm 0;
        };
        if ($@) {
          die "$@" unless $@ eq "alarm\n";  # unexpected errors
          say "Timed out after $to seconds!";
          $self->sys($docker, "kill", $name);
          say "Killed docker container $name";
        }

        if ($self->is_covered($d)) {
          $self->set_covered($d);
          say "$d done";
        } else {
          $self->set_failed($d);
          say "$d failed";
        }
      },
      do { my %m; [ sort grep !$m{$_}++, @$modules ] }
    );
  }

  method get_latest {
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
}

# class() function defined outside class block due to keyword conflict
sub class {
  my ($pc) = @_;
      $pc eq "n/a" ? "na"
    : $pc < 75     ? "c0"
    : $pc < 90     ? "c1"
    : $pc < 100    ? "c2"
    :                "c3"
}

package Devel::Cover::Collection::Template::Provider;

use strict;
use warnings;

# VERSION

use base "Template::Provider";

my %Templates;

sub fetch ($self, $name, $) {
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
  "https://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="https://www.w3.org/1999/xhtml">
<!--
This file was generated by Devel::Cover Version $VERSION
Devel::Cover is copyright 2001-2025, Paul Johnson (paul\@pjcj.net)
Devel::Cover is free. It is licensed under the same terms as Perl itself.
The latest version of Devel::Cover should be available from my homepage:
https://pjcj.net
-->
[% PROCESS colours %]
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8"></meta>
  <meta http-equiv="Content-Language" content="en-us"></meta>
  <link rel="stylesheet" type="text/css"
        href="/[% subdir %]collection.css"></link>
  <title> [% title %] </title>
</head>
<body>
  [% content %]
  <hr/>
  <p>
  Coverage information from <a href="https://metacpan.org/module/Devel::Cover">
    Devel::Cover
  </a> by <a href="https://pjcj.net">Paul Johnson</a>.

  <br/>

  Please report problems with this site to the
  <a href="https://github.com/pjcj/Devel--Cover/issues">issue tracker</a>.</p>

  <p><a href="http://cpancover.com/latest/about.html">About</a> the project.</p>

  <p>This server generously donated by
  <a href="https://www.bytemark.co.uk">Bytemark</a>.</p>
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

<p>CPANCover is a project to provide code coverage information for
<a href="https://metacpan.org">CPAN</a> modules.  When a new module, or an
update to an existing module, is uploaded to CPAN it will automatically be
downloaded by
CPANCover.  CPANCover will run the module's tests and measure the code coverage
provided by the tests.  This information is then made available as HTML pages
and JSON data.</p>

<p>The coverage data is generated by <a
href="https://metacpan.org/release/Devel-Cover">Devel::Cover</a>.

<p>The source code is available at the
  <a href="https://github.com/pjcj/Devel--Cover">GitHub repository</a>.
  Contributions are also accepted for several
  <a href="https://pjcj.net/devel-cover/projects.html">open projects</a>.
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
Anything you still can't cope with is therefore your own problem.
"

__END__

=head1 NAME

Devel::Cover::Collection - Code coverage for a collection of modules

=head1 SYNOPSIS

  use Devel::Cover::Collection;

  my $collection = Devel::Cover::Collection->new(
    results_dir => "/path/to/results",
    bin_dir     => "/path/to/bin",
    workers     => 4,
    verbose     => 1,
  );

  # Add modules to process
  $collection->add_modules("Some::Module", "Another::Module");

  # Or load from a file
  $collection->set_module_file("/path/to/modules.txt");
  $collection->process_module_file;

  # Run coverage collection
  $collection->cover_modules;

  # Generate HTML reports
  $collection->generate_html;

=head1 DESCRIPTION

Devel::Cover::Collection provides infrastructure for running code coverage
analysis across a collection of CPAN modules. It is primarily used by the
CPANCover service (L<http://cpancover.com>) to generate coverage reports for
CPAN distributions.

The module supports:

=over 4

=item * Parallel processing of multiple modules

=item * Docker-based isolation for coverage runs

=item * HTML and JSON report generation

=item * Tracking of covered and failed modules

=item * Compression of old coverage results

=back

This module requires Perl 5.42.0 or later and uses the builtin C<class> feature.

=head1 CONSTRUCTOR

=head2 new

  my $collection = Devel::Cover::Collection->new(%options);

Creates a new Collection object. All options are optional and have sensible
defaults.

=head1 ATTRIBUTES

=head2 Read-Only Attributes

These attributes can only be set via the constructor.

=head3 bin_dir

Directory containing the C<cover> binary. Used when running coverage commands.

=head3 cpancover_dir

Directory for CPANCover-specific files and configuration.

=head3 cpan_dir

An arrayref of CPAN directories to search for build directories. Defaults to
C<~/.cpan> and C<~/.local/share/.cpan> if they exist.

=head3 results_dir

Directory where coverage results are stored. Required for most operations.

=head3 dryrun

Boolean. If true, commands are printed but not executed. Default: 0.

=head3 env

Environment identifier (e.g., 'prod', 'dev'). Default: 'prod'.

=head3 force

Boolean. If true, re-run coverage even for already-covered modules.
Default: 0.

=head3 output_file

Filename for the main output file. Default: 'index.html'.

=head3 report

Report format to generate. Default: 'html_basic'.

=head3 timeout

Timeout in seconds for coverage runs. Default: 1800 (30 minutes).

=head3 verbose

Boolean. If true, print additional progress information. Default: 0.

=head3 workers

Number of parallel workers for coverage runs. Default: 0 (no parallelism).

=head3 docker

Docker command to use. Default: 'docker'.

=head3 local

Boolean. If true, run in local mode without Docker. Default: 0.

=head2 Read-Write-Private Attributes

These attributes have public readers but private setters. Use the provided
methods to modify them.

=head3 build_dirs

Arrayref of build directories to process. Modify via C<add_build_dirs>.

=head3 modules

Arrayref of module names to process. Modify via C<add_modules> or
C<set_modules>.

=head3 module_file

Path to a file containing module names (one per line). Set via
C<set_module_file>.

=head2 Read-Write Attributes

These attributes can be read and written directly.

=head3 dir

  $collection->dir("/path/to/dir");
  my $dir = $collection->dir;

Working directory for the current operation.

=head3 file

  $collection->file("/path/to/file");
  my $file = $collection->file;

Current file being processed.

=head1 METHODS

=head2 Module Management

=head3 add_modules

  $collection->add_modules(@module_names);

Appends modules to the list of modules to process.

=head3 set_modules

  $collection->set_modules(@module_names);

Replaces the entire module list with the given modules.

=head3 set_module_file

  $collection->set_module_file("/path/to/modules.txt");

Sets the path to a file containing module names.

=head3 process_module_file

  $collection->process_module_file;

Reads module names from the file specified by C<module_file> and adds them
to the modules list. Blank lines and lines starting with C<#> are ignored.

=head2 Build Operations

=head3 build_modules

  $collection->build_modules;

Builds all modules in the modules list using C<cpan -Ti>. If C<force> is
true, uses the C<-f> flag.

=head3 add_build_dirs

  $collection->add_build_dirs;

Scans the CPAN directories for build directories and adds them to
C<build_dirs>.

=head3 local_build

  $collection->local_build;

Orchestrates a complete local build workflow: processes the module file,
builds modules, adds build directories, and runs coverage on all.

=head2 Coverage Operations

=head3 run

  $collection->run($build_dir);

Runs coverage analysis on a single build directory. Creates coverage reports
in the results directory.

=head3 run_all

  $collection->run_all;

Runs coverage analysis on all directories in C<build_dirs>, using parallel
workers if configured.

=head3 cover_modules

  $collection->cover_modules;

Covers all modules using Docker containers. Processes the module file,
then runs coverage for each module in parallel.

=head2 Report Generation

=head3 generate_html

  $collection->generate_html;

Generates HTML coverage reports for all modules in the results directory.
Creates an index page, per-module pages, and an about page.

=head3 write_summary

  $collection->write_summary($vars);

Writes the HTML summary pages using Template Toolkit. Called by
C<generate_html>.

=head3 write_json

  $collection->write_json($vars);

Writes a JSON file (C<cpancover.json>) containing coverage data for all
modules.

=head2 Status Tracking

=head3 is_covered

  if ($collection->is_covered($module_dir)) { ... }

Returns true if coverage results exist for the given module directory.

=head3 is_failed

  if ($collection->is_failed($module_dir)) { ... }

Returns true if the module has been marked as failed.

=head3 set_covered

  $collection->set_covered($module_dir);

Marks a module as successfully covered (removes any failure marker).

=head3 set_failed

  $collection->set_failed($module_dir);

Marks a module as failed by creating a timestamp file in the failed
directory.

=head2 Path Methods

=head3 made_res_dir

  my ($path, $output) = $collection->made_res_dir;
  my ($path, $output) = $collection->made_res_dir($subdir);

Creates and returns the results directory path. If C<$subdir> is provided,
creates that subdirectory within the results directory.

=head3 covered_dir

  my $path = $collection->covered_dir($module_dir);

Returns the path where coverage results for a module are stored.

=head3 failed_dir

  my $path = $collection->failed_dir;

Returns the path to the directory containing failure markers.

=head3 failed_file

  my $path = $collection->failed_file($module_dir);

Returns the path to the failure marker file for a module.

=head3 dc_file

  my $path = $collection->dc_file;

Returns the path to the C<dc> utility script.

=head2 Maintenance

=head3 compress_old_versions

  $collection->compress_old_versions($num_versions_to_keep);

Compresses old coverage results, keeping only the specified number of most
recent versions for each module.

=head3 get_latest

  $collection->get_latest;

Fetches and prints the latest CPAN release information using
L<CPAN::Releases::Latest>.

=head2 System Commands

=head3 sys

  my $output = $collection->sys(@command);

Runs a system command, displaying the first portion of output immediately
and buffering the rest. Returns the output on success, empty string on
failure.

=head3 bsys

  my $output = $collection->bsys(@command);

Like C<sys>, but buffers all output (no immediate display).

=head3 fsys

  my $output = $collection->fsys(@command);

Like C<sys>, but dies on failure.

=head3 fbsys

  my $output = $collection->fbsys(@command);

Like C<bsys>, but dies on failure.

=head1 FUNCTIONS

=head2 class

  my $css_class = Devel::Cover::Collection::class($percentage);

Converts a coverage percentage to a CSS class name for HTML reports:

  n/a     -> "na"
  < 75    -> "c0"
  < 90    -> "c1"
  < 100   -> "c2"
  100     -> "c3"

=head1 EMBEDDED CLASSES

=head2 Devel::Cover::Collection::Template::Provider

A subclass of L<Template::Provider> that provides built-in templates for
HTML report generation. The following templates are available:

=over 4

=item * colours - CSS colour definitions

=item * html - Base HTML wrapper

=item * summary - Main index page

=item * about - About page

=item * module_by_start - Module listing by first letter

=back

=head1 DEPENDENCIES

=over 4

=item * Perl 5.42.0 or later (for builtin C<class> feature)

=item * L<Devel::Cover::DB>

=item * L<JSON::MaybeXS>

=item * L<Parallel::Iterator>

=item * L<Template>

=item * L<Time::HiRes>

=back

=head1 SEE ALSO

L<Devel::Cover>, L<http://cpancover.com>

=head1 AUTHOR

Paul Johnson E<lt>paul@pjcj.netE<gt>

=head1 LICENCE

Copyright 2014-2025, Paul Johnson (paul@pjcj.net)

This software is free. It is licensed under the same terms as Perl itself.

The latest version of this software should be available on CPAN and from my
homepage: L<https://pjcj.net/>.

=cut

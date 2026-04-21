# Copyright 2014-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Collection;

use 5.42.0;

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

my $Dist_ext_re = qr/\.(?:zip|tgz|tar\.(?:gz|bz2|xz))/;

class Devel::Cover::Collection {
  # ro attributes
  field $bin_dir       :param :reader = undef;
  field $cpancover_dir :param :reader = undef;
  field $cpan_dir      :param :reader = undef;
  field $results_dir   :param :reader = undef;
  field $dryrun        :param :reader = undef;
  field $env           :param :reader = undef;
  field $force         :param :reader = undef;
  field $output_file   :param :reader = undef;
  field $report        :param :reader = undef;
  field $timeout       :param :reader = undef;
  field $verbose       :param :reader = undef;
  field $workers       :param :reader = undef;
  field $docker        :param :reader = undef;
  field $local         :param :reader = undef;

  # rwp attributes (reader + private setter)
  field $build_dirs  :param :reader = undef;
  field $modules     :param :reader = undef;
  field $module_file :param :reader = undef;

  # rebuild state
  field $rebuild       :param :reader = undef;
  field $rebuild_batch :param :reader = undef;

  # rw attributes (custom accessors for Moo compatibility)
  field $dir  :param = undef;
  field $file :param = undef;

  ADJUST {
    # Apply defaults (equivalent to BUILDARGS)
    $build_dirs    //= [];
    $cpan_dir      //= [grep -d, glob "~/.cpan ~/.local/share/.cpan"];
    $docker        //= "docker";
    $dryrun        //= 0;
    $env           //= "prod";
    $force         //= 0;
    $local         //= 0;
    $modules       //= [];
    $output_file   //= "index.html";
    $rebuild       //= 0;
    $rebuild_batch //= 100;
    $report        //= "html";
    $timeout       //= $ENV{CPANCOVER_TIMEOUT} // 30 * 60;  # half an hour
    $verbose       //= 0;
    $workers       //= 0;
    $ENV{CPANCOVER_TIMEOUT} = $timeout;
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
    local $_;  # while (<$fh>) below would clobber caller's $_
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

  method add_modules     (@o) { push @$modules, @o }
  method set_modules     (@o) { @$modules = @o }
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
    for my $module (sort grep !$m{$_}++, @$modules) {
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
    push @$build_dirs, grep { !$exists->() } grep -d, map glob("$_/build/*"),
      @$cpan_dir;
  }

  method filter_build_dirs_to_targets {
    my %target = map { (s|.*/||r =~ s/${Dist_ext_re}$//r) => 1 } @$modules;
    $build_dirs = [
      grep {
        my $name = (s|.*/||r) =~ s/-\d+$//r;
        $target{$name};
      } @$build_dirs
    ];
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
    $output .= $self->fbsys(
      @cmd, "--test", "--report", $report, "--outputfile", $output_file
    );
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
      $build_dirs,
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

  method coverage_class ($pc) {
        $pc eq "n/a" ? "na"
      : $pc < 75     ? "c0"
      : $pc < 90     ? "c1"
      : $pc < 100    ? "c2"
      : "c3"
  }

  method write_summary ($vars) {
    my $d = $self->dir;
    my $f = $self->file;

    write_file(($self->made_res_dir)[0], "collection.css");
    write_file(($self->made_res_dir)[0], "collection.js");
    my $template = Template->new({
      LOAD_TEMPLATES =>
        [Devel::Cover::Collection::Template::Provider->new({})],
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

  method resolve_log_links ($d, $mods, $vars) {
    # Match top-level .out.gz log files to modules
    my $n   = 0;
    my $re  = qr/^\w-\w\w-\w+-(.*)/;
    my $ext = qr/($Dist_ext_re)/;
    my $ts  = qr/--\d{10,11}\.\d{6}\.out\.gz$/;
    for my $f (@$mods) {
      my ($module) = $f =~ /${re}${ext}${ts}/ or next;
      next if $vars->{vals}{$module}{log};
      $vars->{vals}{$module}{log} = $f;
      print "-" if !($n++ % 1000) && !$verbose;
    }

    # Fallback: .log_ref for modules built as dependencies
    $n = 0;
    for my $module (keys $vars->{vals}->%*) {
      next if $vars->{vals}{$module}{log};
      my $ref = "$d/$module/.log_ref";
      open my $fh, "<", $ref or next;
      chomp(my $log = <$fh>);
      close $fh or warn "Can't close $ref: $!";
      $vars->{vals}{$module}{log} = $log if length $log;
      print "-"                          if !($n++ % 1000) && !$verbose;
    }
    say "";
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
        [grep !/path|time/, @Devel::Cover::DB::Criteria_short, "total"],
      criteria    => [grep !/path|time/, @Devel::Cover::DB::Criteria, "total"],
      col_headers => do {
        my @f = (grep(!/path|time/, @Devel::Cover::DB::Criteria), "total");
        my @s
          = (grep(!/path|time/, @Devel::Cover::DB::Criteria_short), "total");
        [map { { full => ucfirst($f[$_]), short => $s[$_] } } 0 .. $#f]
      },
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
        $m->{$criterion}{class} = $self->coverage_class($pc);
        $m->{$criterion}{details}
          = ($summary->{covered} || 0) . " / " . ($summary->{total} || 0);
      }

      print "." if !($n++ % 1000) && !$verbose;
    }

    $self->resolve_log_links($d, \@mods, $vars);

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
      my $run = $runs[0] // next;
      push $mods{$name}->@*, { dir => $entry, start => $run->{start} // 0 };
    }

    for my $name (sort keys %mods) {
      # print Dumper $mods{$name};
      my @o = sort { $b->{start} <=> $a->{start} } $mods{$name}->@*;
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
    $self->filter_build_dirs_to_targets;
    $self->run_all;
  }

  method failed_dir { ($self->made_res_dir("__failed__"))[0] }
  method covered_dir ($d) { $results_dir . "/$d" }
  method failed_file ($d) { $self->failed_dir . "/$d" }

  method is_covered ($d) {
    -d $self->covered_dir($d) && (!$rebuild || $self->is_rebuilt($d))
  }

  method is_failed ($d) {
    -e $self->failed_file($d) && (!$rebuild || $self->is_rebuilt($d))
  }
  method set_covered ($d) { unlink $self->failed_file($d) }

  method set_failed ($d) {
    my $ff = $self->failed_file($d);
    open my $fh, ">", $ff or return warn "Can't open $ff: $!";
    print $fh scalar localtime;
    close $fh or warn "Can't close $ff: $!";
  }

  method rebuilt_dir { ($self->made_res_dir("__rebuilt__"))[0] }
  method rebuilt_file ($d) { $self->rebuilt_dir . "/$d" }
  method is_rebuilt   ($d) { -e $self->rebuilt_file($d) }

  method set_rebuilt ($d) {
    my $rf = $self->rebuilt_file($d);
    open my $fh, ">", $rf or return warn "Can't open $rf: $!";
    print $fh scalar localtime;
    close $fh or warn "Can't close $rf: $!";
  }

  method unflag_all_rebuilt { $self->fsys("rm", "-rf", $self->rebuilt_dir) }

  method known_distdirs {
    my %seen;
    if (defined $results_dir && -d $results_dir) {
      opendir my $dh, $results_dir or die "Can't opendir $results_dir: $!";
      for my $e (readdir $dh) {
        next          if $e =~ /^\./ || $e =~ /^__/;
        $seen{$e} = 1 if -e "$results_dir/$e/cover.json";
      }
      closedir $dh or warn "Can't closedir $results_dir: $!";
    }
    my $fd = $self->failed_dir;
    opendir my $dh, $fd or die "Can't opendir $fd: $!";
    for my $e (readdir $dh) {
      next if $e =~ /^\./;
      $seen{$e} = 1;
    }
    closedir $dh or warn "Can't closedir $fd: $!";
    sort keys %seen
  }

  method all_rebuilt {
    $self->is_rebuilt($_) or return 0 for $self->known_distdirs;
    1
  }

  method next_rebuild_batch {
    return () if $rebuild_batch <= 0;
    my @pending  = grep !$self->is_rebuilt($_), $self->known_distdirs;
    my @decorate = map {
      my $cover = $self->covered_dir($_) . "/cover.json";
      my $mtime = (stat $cover)[9] // (stat $self->failed_file($_))[9] // 0;
      [$_, $mtime]
    } @pending;
    my @sorted = map $_->[0], sort { $a->[1] <=> $b->[1] } @decorate;
    @sorted > $rebuild_batch ? @sorted[0 .. $rebuild_batch - 1] : @sorted
  }

  method cpan_path_for ($distdir) {
    my $bare = $distdir =~ s/-\d[\d.]*$//r;
    my $out  = $self->bsys("cpanm", "--info", $bare);
    chomp $out;
    length $out ? $out : undef
  }

  method rebuild_pass {
    my @candidates = $self->next_rebuild_batch;
    return 0 unless @candidates;
    my @paths;
    for my $d (@candidates) {
      if (defined(my $path = $self->cpan_path_for($d))) {
        push @paths, $path;
      } else {
        say "Purging defunct $d";
        $self->sys("rm", "-rf", $self->covered_dir($d));
        unlink $self->failed_file($d);
        unlink $self->rebuilt_file($d);
      }
    }
    return 0 unless @paths;
    $self->set_modules(@paths);
    $self->cover_modules;
    scalar @paths
  }

  method write_status (%counts) {
    my ($rdir) = $self->made_res_dir;
    my $f = "$rdir/.cpancover_status";
    open my $fh, ">", $f or return warn "Can't open $f: $!";
    for my $k (sort keys %counts) {
      print $fh "$k=$counts{$k}\n";
    }
    close $fh or warn "Can't close $f: $!";
  }

  method dc_file {
    my $d = "";
    $d = "/dc/" if $local && -d "/dc";
    "${d}utils/dc"
  }

  method cover_modules {
    $self->process_module_file;
    # say "modules: ", Dumper $modules;

    local $ENV{CPANCOVER_REBUILD} = 1 if $rebuild;
    my @cmd = ($self->dc_file, "--env", $env);
    push @cmd, "--results_dir", $results_dir if defined $results_dir;
    push @cmd, "--verbose" if $verbose;
    my @command = (@cmd, "cpancover-docker-module");
    my @res     = iterate_as_array(
      { workers => $workers },
      sub {
        # say "mod ", Dumper \@_;
        my (undef, $module) = @_;
        my $d = $module =~ s|.*/||r =~ s/${Dist_ext_re}$//r;
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

        if (-d $self->covered_dir($d)) {
          $self->set_covered($d);
          say "$d done";
        } else {
          $self->set_failed($d);
          say "$d failed";
        }
        $self->set_rebuilt($d) if $rebuild;
      },
      do { my %m; [sort grep !$m{$_}++, @$modules] },
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

$Templates{html} = <<'EOT';
<!DOCTYPE html>
<html lang="en">
<!--
This file was generated by Devel::Cover Version $VERSION
Devel::Cover is copyright 2001-2026, Paul Johnson (paul\@pjcj.net)
Devel::Cover is free. It is licensed under the same terms as Perl itself.
The latest version of Devel::Cover should be available from my homepage:
https://pjcj.net
-->
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="/[% subdir %]collection.css">
<link rel="icon" href="data:image/svg+xml,
  <svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'>
  <circle cx='8' cy='8' r='7' fill='%232e7d32'/>
  </svg>">
<title>[% title || "CPANCover" %] - Devel::Cover</title>
</head>
<body>
<header class="header">
<div class="header-inner">
<h1>CPANCover</h1>
<div class="header-stats">
<button class="theme-toggle" aria-label="Toggle dark mode">&#x263e;</button>
</div>
</div>
</header>
<main class="content">
[% content %]
</main>
<footer class="footer">
Coverage information from
<a href="https://metacpan.org/module/Devel::Cover">Devel::Cover</a>
by <a href="https://pjcj.net">Paul Johnson</a>.
Please report problems to the
<a href="https://github.com/pjcj/Devel--Cover/issues">bug tracker</a>.
<a href="/[% subdir %]about.html">About</a> the project.
This server generously donated by
<a href="https://www.bytemark.co.uk">Bytemark</a>.
</footer>
<script src="/[% subdir %]collection.js" defer></script>
</body>
</html>
EOT

$Templates{summary} = <<'EOT';
[% WRAPPER html %]

<h2>Distributions</h2>

<p>Search for distributions by first character:</p>

<div class="az-nav">
[% FOREACH start = modules.keys.sort %]
  <a href="dist/[%- start -%].html">[% start %]</a>
[% END %]
</div>

[% END %]
EOT

$Templates{about} = <<'EOT';
[% WRAPPER html %]

<h2>About CPANCover</h2>

<p>CPANCover provides code coverage information for
<a href="https://metacpan.org">CPAN</a> modules. When a module is uploaded
to CPAN, CPANCover automatically downloads it, runs its tests, and measures
code coverage using
<a href="https://metacpan.org/release/Devel-Cover">Devel::Cover</a>.
Results are published as HTML pages and JSON data.</p>

<h3>Coverage key</h3>

<table class="about-key">
<thead>
<tr>
  <th>Coverage</th>
  <th>Meaning</th>
</tr>
</thead>
<tbody>
<tr>
  <td class="c3">100%
    <span class="cov-bar">
    <span class="cov-bar-fill" style="width:100%"></span>
    </span>
  </td>
  <td>Full coverage</td>
</tr>
<tr>
  <td class="c2">90 - 99%
    <span class="cov-bar">
    <span class="cov-bar-fill" style="width:95%"></span>
    </span>
  </td>
  <td>Good coverage</td>
</tr>
<tr>
  <td class="c1">75 - 89%
    <span class="cov-bar">
    <span class="cov-bar-fill" style="width:82%"></span>
    </span>
  </td>
  <td>Partial coverage</td>
</tr>
<tr>
  <td class="c0">&lt; 75%
    <span class="cov-bar">
    <span class="cov-bar-fill" style="width:50%"></span>
    </span>
  </td>
  <td>Low coverage</td>
</tr>
</tbody>
</table>

<h3>Links</h3>

<div class="az-nav">
<a href="https://github.com/pjcj/Devel--Cover">Source code on GitHub</a>
<a href="https://metacpan.org/release/Devel-Cover">Devel::Cover on
MetaCPAN</a>
</div>

[% END %]
EOT

$Templates{module_by_start} = <<'EOT';
[% WRAPPER html %]

<h2>Distributions - [% module_start %]</h2>

[% crit_w = 76 / col_headers.size %]
<table>
<colgroup>
<col style="width:12%">
<col style="width:7%">
<col style="width:5%">
[% FOREACH h = col_headers %]
<col style="width:[% crit_w %]%">
[% END %]
</colgroup>

  [% IF modules.$module_start %]
    <tr>
      <th>Module</th>
      <th>Version</th>
      <th>Log</th>
      [% FOREACH h = col_headers %]
        <th>
          <span class="name-full">[% h.full %]</span>
          <span class="name-short">[% h.short %]</span>
        </th>
      [% END %]
    </tr>
  [% END %]

  [% FOREACH module = modules.$module_start %]
    [% m = module.module %]
    <tr>
      <td>
        [% IF vals.$m.link %]
          <a href="/[% subdir %][%- vals.$m.link -%]">
            [% module.name || module.module %]
          </a>
        [% ELSE %]
          [% module.name || module.module %]
        [% END %]
      </td>
      <td>[% module.version %]</td>
      <td>
        [% IF vals.$m.log %]
          <a href="/[% subdir %][% vals.$m.log %]">&para;</a>
        [% END %]
      </td>
      [% FOREACH criterion = criteria %]
        [% pc = vals.$m.$criterion.pc %]
        <td class="[%- vals.$m.$criterion.class %] tip-hover">
          [% pc %]
          [% IF pc != 'n/a' %]
          <span class="cov-bar">
          <span class="cov-bar-fill"
            style="width:[% pc %]%"></span>
          </span>
          [% END %]
          <span class="glass-tip">[%- vals.$m.$criterion.details -%]</span>
        </td>
      [% END %]
    </tr>
  [% END %]

</table>

[% END %]
EOT

"
We have normality, I repeat we have normality.
Anything you still can't cope with is therefore your own problem.
"

__END__

=encoding utf8

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

=head3 rebuild

Boolean. If true, cpancover is running in rebuild mode: already-covered
distributions are reprocessed so their results reflect the current
Devel::Cover and the current default report. Default: 0.

=head3 rebuild_batch

Maximum number of distdirs returned by C<next_rebuild_batch> in a single
call. C<0> disables the rebuild pass (C<next_rebuild_batch> returns an
empty list). Default: 100.

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

=head3 filter_build_dirs_to_targets

  $collection->filter_build_dirs_to_targets;

Reduces C<build_dirs> to those entries whose basename (with the trailing
C<< -<n> >> CPAN counter stripped) matches a distdir name derived from
C<modules>. Used after C<add_build_dirs> so that dependency build
directories pulled in by C<cpan -Ti> are not covered alongside the target
distribution.

=head3 local_build

  $collection->local_build;

Orchestrates a complete local build workflow: processes the module file,
builds modules, adds build directories, filters them to the target
distributions, and runs coverage on all.

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

=head3 coverage_class

  my $css_class = $collection->coverage_class($percentage);

Converts a coverage percentage to a CSS class name for HTML reports:

  n/a     -> "na"
  < 75    -> "c0"
  < 90    -> "c1"
  < 100   -> "c2"
  100     -> "c3"

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
In rebuild mode (C<$rebuild> is true), also requires that the distdir
has been flagged as rebuilt this cycle; already-covered but not-yet-
rebuilt distdirs return false so C<cover_modules> will re-process them.

=head3 is_failed

  if ($collection->is_failed($module_dir)) { ... }

Returns true if the module has been marked as failed. In rebuild mode,
requires the distdir to have been flagged as rebuilt this cycle for
the same reason as C<is_covered>.

=head3 set_covered

  $collection->set_covered($module_dir);

Marks a module as successfully covered (removes any failure marker).

=head3 set_failed

  $collection->set_failed($module_dir);

Marks a module as failed by creating a timestamp file in the failed
directory.

=head2 Rebuild State

Rebuild state mirrors the failure-tracking family above, but is used to
drive gradual regeneration of already-covered distributions when the
Devel::Cover version or default report has changed. State is persisted on
disk under C<< $results_dir/__rebuilt__/ >>, parallel to C<__failed__>.

=head3 rebuilt_dir

  my $path = $collection->rebuilt_dir;

Returns the path to the directory containing rebuild markers, creating
it if necessary.

=head3 rebuilt_file ($module_dir)

  my $path = $collection->rebuilt_file($module_dir);

Returns the path to the rebuild marker file for a distdir.

=head3 is_rebuilt ($module_dir)

  if ($collection->is_rebuilt($module_dir)) { ... }

Returns true if the distdir has been flagged as rebuilt in this cycle.

=head3 set_rebuilt ($module_dir)

  $collection->set_rebuilt($module_dir);

Marks a distdir as rebuilt by writing a timestamp file in the rebuilt
directory. Called on any outcome (success or failure) in rebuild mode so
the entry does not get retried before the cycle completes.

=head3 unflag_all_rebuilt

  $collection->unflag_all_rebuilt;

Removes the rebuilt directory and all its markers. Called at the end of
a rebuild cycle once every known distdir has been processed.

=head3 known_distdirs

  my @d = $collection->known_distdirs;

Returns the union of distdirs with a C<cover.json> under C<$results_dir>
and distdirs named by markers under C<__failed__/>. Used to define the
rebuild queue.

=head3 all_rebuilt

  if ($collection->all_rebuilt) { ... }

Returns true if every entry in C<known_distdirs> has a rebuild marker
(or if C<known_distdirs> is empty).

=head3 next_rebuild_batch

  my @batch = $collection->next_rebuild_batch;

Returns up to C<rebuild_batch> distdirs that have not yet been rebuilt,
oldest first by the mtime of their C<cover.json> (or their C<__failed__/>
marker when no cover.json exists). Returns an empty list when
C<rebuild_batch> is not positive.

=head3 cpan_path_for ($distdir)

  my $path = $collection->cpan_path_for("Foo-Bar-1.23");

Maps a distdir back to a CPAN release path (e.g. C<< AUTHOR/Foo-Bar-
1.23.tar.gz >>) by running C<cpanm --info> on the bare distribution
name. Returns undef when the lookup fails. Used by C<rebuild_pass> to
feed distdirs from C<next_rebuild_batch> into C<cover_modules>, which
expects CPAN paths rather than distdirs.

=head3 rebuild_pass

  my $n = $collection->rebuild_pass;

Runs one batch of the rebuild queue: pulls distdirs from
C<next_rebuild_batch>, resolves each to a CPAN path via
C<cpan_path_for>, sets C<modules> to the resulting list, and invokes
C<cover_modules>. A distdir whose lookup fails is treated as no longer
on CPAN and purged: the distdir itself, its C<__failed__/> marker, and
its C<__rebuilt__/> marker are all removed. Returns the number of
modules fed to C<cover_modules> (zero if the queue is empty or every
lookup failed). Intended to be called from the rebuild loop recipe in
C<utils/dc>.

=head3 write_status (%counts)

  $collection->write_status(
    new_count     => 4,
    rebuilt_count => 100,
    all_rebuilt   => 0,
  );

Writes a one-line-per-key C<key=value> file at
C<< $results_dir/.cpancover_status >>. The rebuild loop recipe reads
this file between passes to decide whether to regenerate the top-level
HTML and whether the rebuild cycle has finished.

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

Copyright 2014-2026, Paul Johnson (paul@pjcj.net)

This software is free. It is licensed under the same terms as Perl itself.

The latest version of this software should be available on CPAN and from my
homepage: L<https://pjcj.net/>.

=cut

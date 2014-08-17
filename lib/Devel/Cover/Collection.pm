# Copyright 2014, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Collection;

use 5.16.0;
use warnings;

# VERSION

use Devel::Cover::DB;
use Devel::Cover::DB::IO::JSON;
use Devel::Cover::Dumper;

use Parallel::Iterator "iterate_as_array";
use POSIX              "setsid";
use Template;
use Time::HiRes        "time";

use Class::XSAccessor ();
use Moo;
use namespace::clean;
use warnings FATAL => "all";  # be explicit since Moo sets this

my %A = (
    ro  => [ qw( bin_dir cpancover_dir cpan_dir results_dir force output_file
                 report timeout verbose workers docker                      ) ],
    rwp => [ qw( build_dirs local_timeout modules module_file               ) ],
    rw  => [ qw(                                                            ) ],
);
while (my ($type, $names) = each %A) { has $_ => (is => $type) for @$names }

sub BUILDARGS {
    my $class = shift;
    my (%args) = @_;
    {
        build_dirs      => [],
        cpan_dir        => [grep -d, glob("~/.cpan ~/.local/share/.cpan")],
        docker          => "docker",
        force           => 0,
        local_timeout   => 0,
        modules         => [],
        output_file     => "index.html",
        report          => "html_basic",
        timeout         => 1800,  # half an hour
        verbose         => 0,
        workers         => 0,
        %args,
    }
};

# display $non_buffered characters, then buffer
sub _sys {
    my $self = shift;
    my ($non_buffered, @command) = @_;
    my ($output1, $output2) = ("", "");
    $output1 = "dc -> @command\n" if $self->verbose;
    my $timeout = $self->local_timeout || $self->timeout || 30 * 60;
    my $max = 4e4;
    # say "Setting alarm for $timeout seconds";
    my $pid;
    eval {
        open STDIN, "<", "/dev/null" or die "Can't read /dev/null: $!";
        $pid = open my $fh, "-|"     // die "Can't fork: $!";
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
        } else {
            setsid() != -1          or die "Can't start a new session: $!";
            open STDERR, ">&STDOUT" or die "Can't dup stdout: $!";
            exec @command           or die "Can't exec @command: $!";
        }
    };
    if ($@) {
        die "propogate: $@" unless $@ eq "alarm\n";  # propagate unexpected errs
        warn "Timed out after $timeout seconds!\n";
        my $pgrp = getpgrp($pid);
        my $n = kill "-KILL", $pgrp;
        warn "killed $n processes";
    }
    length $output2 ? "$output1\n...\n$output2" : $output1
}

sub sys  { my $self = shift; $self->_sys(4e4, @_) }
sub bsys { my $self = shift; $self->_sys(0,   @_) }

sub add_modules {
    my $self = shift;
    push @{$self->modules}, @_;
}

sub set_modules {
    my $self = shift;
    @{$self->modules} = @_;
}

sub set_module_file {
    my $self = shift;
    my ($file) = @_;
    $self->set_module_file($file);
}

sub process_module_file {
    my $self = shift;
    my $file = $self->module_file;
    return unless defined $file && length $file;
    open my $fh, "<", $file or die "Can't open $file: $!";
    my $modules = do { local $/; <$fh> };
    close $fh or die "Can't close $file: $!";
    my @modules = grep /\S/, grep !/^ *#/, split /\n/, $modules;
    $self->add_modules(@modules);
}

sub build_modules {
    my $self = shift;
    my @command = qw( cpan -i -T );
    push @command, "-f" if $self->force;
    # my @command = qw( cpan );
    # $ENV{CPAN_OPTS} = "-i -T";
    # $ENV{CPAN_OPTS} .= " -f" if $self->force;
    # $self->_set_local_timeout(300);
    my %m;
    for my $module (sort grep !$m{$_}++, @{$self->modules}) {
        say "Building $module";
        my $output = $self->sys(@command, $module);
        say $output;
    }
    $self->_set_local_timeout(0);
}

sub add_build_dirs {
    my $self = shift;
    # say "add_build_dirs"; say for @{$self->build_dirs};
    # say && system "ls -al $_" for "/remote_staging",
                                  # map "$_/build", @{$self->cpan_dir};
    my $exists = sub {
        my $dir = "/remote_staging/" . (s|.*/||r =~ s/-\w{6}$/*/r);
        # say "checking [$dir]";
        my @files = glob $dir;
        @files
    };
    push @{$self->build_dirs},
         grep { !$exists->() }
         grep -d,
         map glob("$_/build/*"), @{$self->cpan_dir};
    # say "add_build_dirs"; say for @{$self->build_dirs};
}

sub run {
    my $self = shift;
    my ($build_dir) = @_;

    my ($module)    = $build_dir =~ m|.*/([^/]+?)(?:-\w{6})$| or return;
    my $db          = "$build_dir/cover_db";
    my $line        = "=" x 80;
    my $output      = "**** Checking coverage of $module ****\n";
    my $results_dir = $self->results_dir // die "No results dir";
    $output        .= $self->sys("mkdir", "-p", $results_dir);
    $results_dir   .= "/$module";

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

    $ENV{DEVEL_COVER_TEST_OPTS} = "-Mblib=" . $self->bin_dir;
    my @cmd = ($^X, $ENV{DEVEL_COVER_TEST_OPTS}, $self->bin_dir . "/cover");
    $output .= $self->bsys(
        @cmd,          "-test",
        "-report",     $self->report,
        "-outputfile", $self->output_file,
    );
    $output .= $self->sys(@cmd, "-report", "json", "-nosummary");

    # TODO - option to merge DB with existing one
    # TODO - portability
    $output .= $self->sys("rm", "-rf", $results_dir);
    $output .= $self->sys("mv", $db, $results_dir);
    $output .= $self->sys("rm", "-rf", $db);

    say "\n$line\n$output$line\n";
}

sub run_all {
    my $self = shift;

    my $results_dir = $self->results_dir // die "No results dir";
    $self->sys("mkdir", "-p", $results_dir);

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

sub write_json {
    my $self = shift;
    my ($vars) = @_;

    # print Dumper $vars;
    my $results = {};
    for my $module (keys %{$vars->{vals}}) {
        my $m   = $vars->{vals}{$module};
        my $mod = $m->{module};
        my ($name, $version) =
            ($mod->{module} // $module) =~ /(.+)-(\d+\.\d+)$/;
        $name    = $mod->{name}     if defined $mod->{name};
        $version = $mod->{version}  if defined $mod->{version};
        if (defined $name && defined $version) {
            $results->{$name}{$version}{coverage}{total} = {
                map { $_ => $m->{$_}{pc} }
                grep $m->{$_}{pc} ne 'n/a',
                grep !/link|module/,
                keys %$m
            };
        } else {
            print "Cannot process $module: ", Dumper $m;
        }
    };
    # print Dumper $vars, $results;

    my $io = Devel::Cover::DB::IO::JSON->new(options => "pretty");
    my $file = $self->results_dir . "/cpancover.json";
    $io->write($results, $file);
    say "Wrote json output to $file";
}

sub class
{
    my ($pc) = @_;
    $pc eq "n/a" ? "na" :
    $pc <    75  ? "c0" :
    $pc <    90  ? "c1" :
    $pc <   100  ? "c2" :
                   "c3"
}

sub generate_html {
    my $self = shift;

    my $d = $self->results_dir;
    chdir $d or die "Can't chdir $d: $!\n";

    my $f = "$d/index.html";
    say "\n\nWriting collection output to $f ...";

    my $vars = {
        title    => "Coverage report",
        modules  => [],
        vals     => {},
        headers  => [ grep !/path|time/,
                           @Devel::Cover::DB::Criteria_short, "total" ],
        criteria => [ grep !/path|time/,
                           @Devel::Cover::DB::Criteria,       "total" ],
    };

    opendir my $dh, $d or die "Can't opendir $d: $!";
    my @modules = sort grep !/^\./, readdir $dh;
    closedir $dh or die "Can't closedir $d: $!";

    for my $module (@modules) {
        my $cover = "$d/$module/cover.json";
        next unless -e $cover;
        say "Adding $module";

        my $io   = Devel::Cover::DB::IO::JSON->new;
        my $json = $io->read($cover);

        my $mod = {
            module => $module,
            map { $_ => $json->{runs}[0]{$_} } qw( name version dir )
        };
        unless (defined $mod->{name} && defined $mod->{version}) {
            my ($name, $version) =
                ($mod->{module} // $module) =~ /(.+)-(\d+\.\d+)$/;
            $mod->{name}    //= $name;
            $mod->{version} //= $version;
        }
        push @{$vars->{modules}}, $mod;

        my $m = $vars->{vals}{$module} = {};
        $m->{module} = $mod;
        $m->{link}   = "$module/index.html"
            if $json->{summary}{Total}{total}{total};

        for my $criterion (@{$vars->{criteria}}) {
            my $summary = $json->{summary}{Total}{$criterion};
            # print "summary:", Dumper $summary;
            my $pc = $summary->{percentage};
            $pc = defined $pc ? sprintf "%.2f", $pc : "n/a";
            $m->{$criterion}{pc}      = $pc;
            $m->{$criterion}{class}   = class($pc);
            $m->{$criterion}{details} =
                ($summary->{covered} || 0) . " / " . ($summary->{total} || 0);
        }
    }
    # print "vars ", Dumper $vars;

    $self->write_stylesheet;
    my $template = Template->new({
        LOAD_TEMPLATES => [
            Devel::Cover::Collection::Template::Provider->new({}),
        ],
    });
    $template->process("summary", $vars, $f) or die $template->error;

    $self->write_json($vars);

    say "Wrote collection output to $f";
}

sub local_build {
    my $self = shift;

    $self->process_module_file;
    $self->build_modules;
    $self->add_build_dirs;
    $self->run_all;
    $self->generate_html;
}

sub failed_dir {
    my $self = shift;
    my $dir = $self->results_dir . "/__failed__";
    -d $dir or mkdir $dir or die "Can't mkdir $dir: $!";
    $dir
}

sub covered_dir {
    my $self = shift;
    my ($dir) = @_;
    $self->results_dir . "/$dir"
}

sub failed_file {
    my $self = shift;
    my ($dir) = @_;
    $self->failed_dir . "/$dir"
}

sub is_covered {
    my $self = shift;
    my ($dir) = @_;
    -d $self->covered_dir($dir)
}

sub is_failed {
    my $self = shift;
    my ($dir) = @_;
    -e $self->failed_file($dir)
}

sub set_covered {
    my $self = shift;
    my ($dir) = @_;
    unlink $self->failed_file($dir);
}

sub set_failed {
    my $self = shift;
    my ($dir) = @_;
    my $ff = $self->failed_file($dir);
    open my $fh, ">", $ff or return warn "Can't open $ff: $!";
    print $fh scalar localtime;
    close $fh or warn "Can't close $ff: $!";
}

sub cover_modules {
    my $self = shift;

    $self->process_module_file;

    my @command = qw( utils/dc cpancover-docker-module );
    $self->_set_local_timeout(0);
    my @res = iterate_as_array(
        { workers => $self->workers },
        sub {
            my (undef, $module) = @_;
            my $dir = $module =~ s|.*/||r
                              =~ s/\.(?:zip|tgz|(?:tar\.(?:gz|bz2)))$//r;
            if ($self->is_covered($dir)) {
                $self->set_covered($dir);
                say "$module already covered";
                return;
            } elsif ($self->is_failed($dir)) {
                say "$module already failed";
                return;
            }

            my $timeout = $self->local_timeout || $self->timeout || 30 * 60;
            # say "Setting alarm for $timeout seconds";
            my $name = sprintf("%s-%18.6f", $module, time)
                         =~ tr/a-zA-Z0-9_./-/cr;
            say "$dir -> $name";
            eval {
                local $SIG{ALRM} = sub { die "alarm\n" };
                alarm $timeout;
                system @command, $module, $name;
                alarm 0;
            };
            if ($@) {
                die "propogate: $@" unless $@ eq "alarm\n";  # unexpected errors
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
        do { my %m; [sort grep !$m{$_}++, @{$self->modules}] }
    );
    $self->_set_local_timeout(0);
}

sub get_latest {
    my $self = shift;

    require CPAN::Releases::Latest;

    my $latest   = CPAN::Releases::Latest->new;
    my $iterator = $latest->release_iterator;

    while (my $release = $iterator->next_release) {
        say $release->path;
        next;
        printf "%s path=%s  time=%d  size=%d\n",
               $release->distname,
               $release->path,
               $release->timestamp,
               $release->size;
    }
}

sub write_stylesheet {
    my $self = shift;

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

sub fetch
{
    my $self = shift;
    my ($name) = @_;
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
Devel::Cover is copyright 2001-2014, Paul Johnson (paul\@pjcj.net)
Devel::Cover is free. It is licensed under the same terms as Perl itself.
The latest version of Devel::Cover should be available from my homepage:
http://www.pjcj.net
-->
[% PROCESS colours %]
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"></meta>
    <meta http-equiv="Content-Language" content="en-us"></meta>
    <link rel="stylesheet" type="text/css" href="collection.css"></link>
    <title> [% title %] </title>
</head>
<body>
    [% content %]
</body>
</html>
EOT

$Templates{summary} = <<'EOT';
[% WRAPPER html %]

<h1> [% title %] </h1>

<table>

    [% IF modules %]
        <tr align="right" valign="middle">
            <th class="header" align="left" style='white-space: nowrap;'> Module </th>
            <th class="header">              Version </th>
            [% FOREACH header = headers %]
                <th class="header"> [% header %] </th>
            [% END %]
        </tr>
    [% END %]

    [% FOREACH module = modules %]
        [% m = module.module %]
        <tr align="right" valign="middle">
            <td align="left">
                [% IF vals.$m.link %]
                    <a href="[%- vals.$m.link -%]">
                        [% module.name || module.module %]
                    </a>
                [% ELSE %]
                    [% module.name || module.module %]
                [% END %]
            </td>
            <td> [% module.version %] </td>
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

<hr/>
Coverage information from <a href="https://metacpan.org/module/Devel::Cover">
  Devel::Cover
</a> by <a href="http://pjcj.net">Paul Johnson</a>.

<br/>

Please report problems with this site to the
<a href="https://github.com/pjcj/Devel--Cover/issues">issue tracker</a>

<br/>
<a href="http://cpancover.com/blead/latest/coverage.html">Core coverage</a>
(under development)

<br/>
<br/>

This server generously donated by
<a href="http://www.bytemark.co.uk/r/cpancover">
  <img src="http://www.bytemark.co.uk/images/subpages/spreadtheword/bytemark_logo_179_x_14.png" alt="bytemark"/>
</a>

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

Copyright 2014, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available on CPAN and from my
homepage: http://www.pjcj.net/.

=cut

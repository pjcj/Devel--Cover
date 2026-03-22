# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Report::Html_crisp;

use v5.20.0;
use strict;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

our $VERSION;

BEGIN {
  # VERSION
}

use Devel::Cover::Html_Common  ## no perlimports
  qw( launch highlight $Have_highlighter );
use Devel::Cover::Truth_Table;  ## no perlimports
use Devel::Cover::Inc ();

BEGIN { $VERSION //= $Devel::Cover::Inc::VERSION }

use HTML::Entities qw( encode_entities );
use Getopt::Long   qw( GetOptions );
use Template 2.00  ();
use File::Path     qw( mkpath );
use List::Util     qw( any );

my $Template;
my %R;
my %Assets;
our %Templates;

my $Threshold = { c0 => 75, c1 => 90, c2 => 100 };

sub class ($pc, $err, $criterion) {
  return "" if $criterion && $criterion eq "time";
  no warnings "uninitialized";
     !$err                   ? "c3"
    : $pc < $Threshold->{c0} ? "c0"
    : $pc < $Threshold->{c1} ? "c1"
    : $pc < $Threshold->{c2} ? "c2"
    :                          "c3"
}

sub oclass ($o, $criterion) {
  $o ? class($o->percentage, $o->error, $criterion) : ""
}

sub _fmt_pc ($pc) {
  return "n/a" unless defined $pc;
  my $x = sprintf "%5.2f", $pc;
  chop $x;
  $x =~ s/^\s+//;
  $x
}

sub _get_summary ($file, $criterion) {
  my $part = $R{db}->summary($file);
  return {} unless exists $part->{$criterion};
  my $c = $part->{$criterion};
  {
    pc      => _fmt_pc($c->{percentage}),
    class   => class($c->{percentage}, $c->{error}, $criterion),
    covered => $c->{covered} || 0,
    total   => $c->{total}   || 0,
    error   => $c->{error}   || 0,
  }
}

sub _build_file_data () {
  my @file_data;
  my $na = { pc => "n/a", class => "", covered => 0, total => 0, error => 0 };
  for my $file ($R{options}{file}->@*) {
    next unless $R{db}->summary($file);
    (my $dir = $file) =~ s{/[^/]+$}{};
    $dir = "" if $dir eq $file;
    (my $basename = $file) =~ s{.*/}{};
    my $meta       = $R{db}->cover->file($file)->{meta} // {};
    my $uncompiled = $meta->{uncompiled} ? 1 : 0;
    my $use_na     = $uncompiled && !$meta->{counts};
    my %f          = (
      name       => $file,
      basename   => $basename,
      dir        => $dir,
      link       => "$R{filenames}{$file}.html",
      exists     => !$uncompiled && -e $file,
      uncompiled => $uncompiled,
      criteria   => {},
    );

    my $risk = 0;

    for my $c ($R{showing}->@*) {
      my $s = $use_na ? $na : _get_summary($file, $c);
      $f{criteria}{$c} = $s;
      $risk += ($s->{error} || 0) if $c =~ /^(?:branch|condition)$/;
    }
    my $total = $use_na ? $na : _get_summary($file, "total");
    $f{total} = $total;
    my $pc = $total->{pc} // "n/a";
    $f{total_pc}   = $pc;
    $f{total_sort} = $pc eq "n/a" ? -1 : $pc;
    $f{risk}       = $risk + (100 - ($pc eq "n/a" ? 0 : $pc));
    push @file_data, \%f;
  } sort {
    ($a->{total_sort} // -1) <=> ($b->{total_sort} // -1)
  } @file_data
}

sub _build_dir_groups ($file_data) {
  my (%dirs, %dir_stats);
  for my $f (@$file_data) {
    my $d = $f->{dir};
    push $dirs{$d}->@*, $f;
    my $s = $dir_stats{$d} ||= { covered => 0, total => 0 };
    my $t = $f->{total};
    $s->{covered} += $t->{covered} || 0;
    $s->{total}   += $t->{total}   || 0;
  } map {
    my $s = $dir_stats{$_};
    my $pc
      = $s->{total}
      ? sprintf("%.1f", 100 * $s->{covered} / $s->{total})
      : "n/a";
    {
      dir   => $_ || "(root)",
      pc    => $pc,
      class => class($pc, ($pc eq "n/a" || $pc < 100) ? 1 : 0, "total"),
      files => $dirs{$_},
    }
  } sort keys %dirs
}

sub _line_subroutines ($f, $n) {
  my $subs = $f->subroutine or return;
  my $loc  = $subs->location($n);
  return unless $loc && @$loc;
  map { {
    name    => encode_entities($_->name),
    covered => $_->covered,
    class   => oclass($_, "subroutine"),
  } } @$loc
}

sub _line_pod ($f, $n) {
  my $pod = $f->pod or return;
  my $loc = $pod->location($n);
  return unless $loc && @$loc;
  map { { covered => $_->covered, class => oclass($_, "pod") } } @$loc
}

sub _line_branches ($f, $n) {
  my $branches = $f->branch or return;
  my $loc      = $branches->location($n);
  return unless $loc && @$loc;
  map { {
    true_count  => $_->value(0),
    false_count => $_->value(1),
    true_class  => class($_->value(0), $_->error(0), "branch"),
    false_class => class($_->value(1), $_->error(1), "branch"),
    text        => encode_entities($_->text // ""),
  } } @$loc
}

sub _line_truth_tables ($f, $n) {
  my $conditions = $f->condition or return;
  my $loc        = $conditions->location($n);
  return unless $loc && @$loc && @$loc <= 16;
  grep { $_->{rows}->@* } map {
    my ($tt, $expr) = @$_;
    my @rows = map { {
      inputs  => [ $_->inputs ],
      result  => $_->result,
      covered => $_->covered,
      class   => $_->covered ? "c3" : "c0",
    } } @$tt;
    {
      expr    => encode_entities($expr),
      rows    => \@rows,
      headers => [ map { chr ord("A") + $_ } 0 .. $rows[0]{inputs}->$#* ],
    }
  } $conditions->truth_table($n)
}

sub _exec_class ($count) {
  defined $count && $count > 0 ? "exec-covered" : "exec-0"
}

sub _line_statement ($f, $n, $line) {
  my $stmt = $f->statement or return;
  my $loc  = $stmt->location($n);
  return unless $loc && @$loc;
  my $s = $loc->[0];
  $line->{count}       = $s->covered;
  $line->{count_class} = oclass($s, "statement");
  $line->{exec_class}  = _exec_class($s->covered);
}

sub _line_partial ($line, $bd, $tts, $sd) {
  return unless defined $line->{count} && $line->{count} > 0;
  my $p;
  $p ||= any { $_->{true_count} == 0 || $_->{false_count} == 0 } @$bd;
  $p ||= any { any { !$_->{covered} } $_->{rows}->@* } @$tts;
  $p ||= any { !$_->{covered} } @$sd;
  $p ||= $line->{pod_uncovered};
  $line->{partial} = 1 if $p;
}

sub _build_source_lines ($file) {
  my $f = $R{db}->cover->file($file);

  open my $fh, "<", $file or warn("Unable to open $file: $!\n"), return [];
  my @all_lines = <$fh>;
  close $fh or die "Can't close $file: $!\n";

  if ($Have_highlighter) {
    my @hl = highlight($R{options}{option}, @all_lines);
    @all_lines = @hl if @hl;
  }

  my @lines;
  my $linen = 1;
  line: while (defined(my $l = shift @all_lines)) {
    my $n = $linen++;
    chomp $l;

    my %line = (number => $n, text => length $l ? $l : "&nbsp;");

    _line_statement($f, $n, \%line);

    my @bd = _line_branches($f, $n);
    $line{branches} = \@bd if @bd;

    my @tts = _line_truth_tables($f, $n);
    $line{truth_tables} = \@tts if @tts;

    my @sd = _line_subroutines($f, $n);
    $line{subroutines} = \@sd if @sd;

    my @pd = _line_pod($f, $n);
    if (@pd) {
      $line{pod}           = \@pd;
      $line{pod_uncovered} = 1 if any { !$_->{covered} } @pd;
    }

    _line_partial(\%line, \@bd, \@tts, \@sd);

    push @lines, \%line;
    last line if $l =~ /^__(END|DATA)__/;
  }

  \@lines
}

sub _write_asset ($dir, $name, $content) {
  my $path = "$dir/$name";
  open my $fh, ">", $path or die "Can't open $path: $!\n";
  print $fh $content;
  close $fh or die "Can't close $path: $!\n";
}

sub get_options ($self, $opt) {
  $opt->{option}{outputfile} = "index.html";
  $opt->{option}{restrict}   = 1;
  $Threshold->{$_}           = $opt->{"report_$_"}
    for grep { defined $opt->{"report_$_"} } qw( c0 c1 c2 );
  die "Invalid command line options"
    unless GetOptions($opt->{option}, qw( noppihtml noperltidy outputfile=s ));
}

sub _set_favicon_colour () {
  my $t  = _get_summary("Total", "total");
  my $pc = $t->{pc};
  $pc = 0 if !defined $pc || $pc eq "n/a";
  my $cl = class($pc, $pc < 100 ? 1 : 0, "total");
  $R{favicon_colour}
    = $cl eq "c0" ? "%23e53935"
    : $cl eq "c1" ? "%23f9a825"
    : $cl eq "c2" ? "%2343a047"
    :               "%232e7d32";
}

sub _totals_for ($file) {
  my %total;
  for my $c ($R{showing}->@*) {
    $total{$c} = _get_summary($file, $c);
  }
  $total{total} = _get_summary($file, "total");
  %total
}

sub _coverage_distribution ($file_data) {
  my %dist = (c0 => 0, c1 => 0, c2 => 0, c3 => 0);
  my @counted
    = grep { !$_->{uncompiled} || $_->{total}{pc} ne "n/a" } @$file_data;
  for my $fd (@counted) {
    my $cl = $fd->{total}{class} || "c3";
    $dist{$cl}++ if exists $dist{$cl};
  }
  $dist{dist_total} = @counted || 1;
  %dist
}

sub _generate_index ($outdir, $options, $file_data, $total, $dist) {
  my @groups = _build_dir_groups($file_data);
  my $vars   = {
    R      => \%R,
    files  => $file_data,
    groups => \@groups,
    total  => $total,
    worst  => [
      @$file_data
      ? (sort { $b->{risk} <=> $a->{risk} } @$file_data)
        [ 0 .. ($#$file_data > 4 ? 4 : $#$file_data) ]
      : ()
    ],
    dist       => $dist,
    dist_total => $dist->{dist_total},
  };
  my $html = "$outdir/$options->{option}{outputfile}";
  $Template->process("index", $vars, $html) or die $Template->error;
}

sub _generate_file_pages ($outdir, $file_data) {
  for my $idx (0 .. $#$file_data) {
    my $fd = $file_data->[$idx];
    next unless $fd->{exists};
    my $file       = $fd->{name};
    my $lines      = _build_source_lines($file);
    my %file_total = _totals_for($file);

    my $prev = $idx > 0            ? $file_data->[ $idx - 1 ] : undef;
    my $next = $idx < $#$file_data ? $file_data->[ $idx + 1 ] : undef;

    my $vars = {
      R         => \%R,
      file      => $fd,
      lines     => $lines,
      total     => \%file_total,
      prev_file => $prev,
      next_file => $next,
    };
    my $html = "$outdir/$fd->{link}";

    $Template->process("file", $vars, $html) or die $Template->error;
  }
}

sub report ($pkg, $db, $options) {
  $Template = Template->new({
    LOAD_TEMPLATES =>
      [ Devel::Cover::Report::Html_crisp::Template::Provider->new({}) ],
  });

  my $fname = (sort keys $db->{runs}->%*)[0] or return;
  my $run   = $db->{runs}{$fname};

  %R = (
    module => { name => $run->name, version => $run->version },
    db     => $db,
    date   => do {
      my @t = localtime;
      sprintf "%04d-%02d-%02d %02d:%02d:%02d", $t[5] + 1900, $t[4] + 1,
        $t[3], $t[2], $t[1], $t[0]
    },
    perl_v  => $^V,
    os      => $^O,
    options => $options,
    version => $VERSION,
    showing => [ grep $options->{show}{$_}, $db->criteria ],
    headers => [
      map  { ($db->criteria_short)[$_] }
      grep { $options->{show}{ ($db->criteria)[$_] } }
        (0 .. $db->criteria - 1)
    ],
    filenames => {
      map { $_ => do { (my $f = $_) =~ s/\W/-/g; $f } } $options->{file}->@*
    },
    threshold      => $Threshold,
    favicon_colour => "%232e7d32",
    report_id      => $options->{outputdir},
    file_count     => 0 + $options->{file}->@*,
  );

  _set_favicon_colour;

  my $outdir = $options->{outputdir};
  my $assets = "$outdir/assets";
  mkpath($assets) unless -d $assets;

  _write_asset($assets, "style.css", $Assets{css});
  _write_asset($assets, "app.js",    $Assets{js});

  my @file_data = _build_file_data;
  my %total     = _totals_for("Total");
  my %dist      = _coverage_distribution(\@file_data);

  _generate_index($outdir, $options, \@file_data, \%total, \%dist);
  _generate_file_pages($outdir, \@file_data);

  my $html = "$outdir/$options->{option}{outputfile}";
  print "HTML output written to $html\n" unless $options->{silent};
}

$Assets{css} = <<'CSS';
/* Devel::Cover Html_crisp report stylesheet */

:root {
  --cov-none-bg: #f8c0c0;
  --cov-none-border: #d32f2f;
  --cov-none-fg: #b71c1c;
  --cov-low-bg: #f8d8a0;
  --cov-low-border: #d08020;
  --cov-low-fg: #8a4a00;
  --cov-good-bg: #f5e880;
  --cov-good-border: #c8a800;
  --cov-good-fg: #8a7000;
  --cov-full-bg: #90d890;
  --cov-full-border: #2e7d32;
  --cov-full-fg: #1b5e20;

  --exec-none: #f09090;
  --exec-partial: #e8d840;
  --exec-covered: #70c870;

  --bg: #ffffff;
  --bg-alt: #e8ecf0;
  --fg: #1a1a1a;
  --fg-muted: #6c757d;
  --border: #dee2e6;
  --link: #1565c0;
  --link-visited: #4a148c;
  --header-bg: #f5f5f5;

  --syn-comment: #7c8a94;
  --syn-keyword: #7b6daa;
  --syn-string: #4a8a52;
  --syn-number: #b8893a;
  --syn-symbol: #4a5568;
  --syn-operator: #5a9991;
  --syn-structure: #7b6daa;
  --syn-core: #5a87ab;
  --syn-pragma: #9a8a3a;
  --syn-magic: #b87a4a;

  --font-body: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
               "Helvetica Neue", Arial, sans-serif;
  --font-code: "SFMono-Regular", Menlo, Monaco, Consolas, "Liberation Mono",
               monospace;
  --font-size-base: 14px;
  --font-size-code: 13px;
  --font-size-small: 12px;
}

@media (prefers-color-scheme: dark) {
  :root {
    --cov-none-bg: #3d1818;
    --cov-none-border: #e05050;
    --cov-none-fg: #f8c8c8;
    --cov-low-bg: #3d2810;
    --cov-low-border: #e08030;
    --cov-low-fg: #f8d0a0;
    --cov-good-bg: #383010;
    --cov-good-border: #d0c020;
    --cov-good-fg: #f0e8a0;
    --cov-full-bg: #143818;
    --cov-full-border: #40b044;
    --cov-full-fg: #b8e8ba;

    --exec-none: #801818;
    --exec-partial: #686000;
    --exec-covered: #1a6828;

    --bg: #1a1a1a;
    --bg-alt: #242424;
    --fg: #e0e0e0;
    --fg-muted: #9e9e9e;
    --border: #424242;
    --link: #64b5f6;
    --link-visited: #ce93d8;
    --header-bg: #2a2a2a;

    --syn-comment: #6a7a84;
    --syn-keyword: #8a84b0;
    --syn-string: #7ab882;
    --syn-number: #cca86a;
    --syn-symbol: #b0b8c0;
    --syn-operator: #8abab4;
    --syn-structure: #8a84b0;
    --syn-core: #8aa8c4;
    --syn-pragma: #ccbe6a;
    --syn-magic: #c89a6a;
  }
}

html[data-theme="dark"] {
  --cov-none-bg: #3d1818;
  --cov-none-border: #e05050;
  --cov-none-fg: #f8c8c8;
  --cov-low-bg: #3d2810;
  --cov-low-border: #e08030;
  --cov-low-fg: #f8d0a0;
  --cov-good-bg: #383010;
  --cov-good-border: #d0c020;
  --cov-good-fg: #f0e8a0;
  --cov-full-bg: #143818;
  --cov-full-border: #40b044;
  --cov-full-fg: #b8e8ba;

  --exec-none: #801818;
  --exec-partial: #686000;
  --exec-covered: #1a6828;

  --bg: #1a1a1a;
  --bg-alt: #242424;
  --fg: #e0e0e0;
  --fg-muted: #9e9e9e;
  --border: #424242;
  --link: #64b5f6;
  --link-visited: #ce93d8;
  --header-bg: #2a2a2a;

  --syn-comment: #6a7a84;
  --syn-keyword: #8a84b0;
  --syn-string: #7ab882;
  --syn-number: #cca86a;
  --syn-symbol: #b0b8c0;
  --syn-operator: #8abab4;
  --syn-structure: #8a84b0;
  --syn-core: #8aa8c4;
  --syn-pragma: #ccbe6a;
  --syn-magic: #c89a6a;
}

html[data-theme="light"] {
  --cov-none-bg: #f8c0c0;
  --cov-none-border: #d32f2f;
  --cov-none-fg: #b71c1c;
  --cov-low-bg: #f8d8a0;
  --cov-low-border: #d08020;
  --cov-low-fg: #8a4a00;
  --cov-good-bg: #f5e880;
  --cov-good-border: #c8a800;
  --cov-good-fg: #8a7000;
  --cov-full-bg: #90d890;
  --cov-full-border: #2e7d32;
  --cov-full-fg: #1b5e20;

  --exec-none: #f09090;
  --exec-partial: #e8d840;
  --exec-covered: #70c870;

  --bg: #ffffff;
  --bg-alt: #e8ecf0;
  --fg: #1a1a1a;
  --fg-muted: #6c757d;
  --border: #dee2e6;
  --link: #1565c0;
  --link-visited: #4a148c;
  --header-bg: #f5f5f5;

  --syn-comment: #7c8a94;
  --syn-keyword: #7b6daa;
  --syn-string: #4a8a52;
  --syn-number: #b8893a;
  --syn-symbol: #4a5568;
  --syn-operator: #5a9991;
  --syn-structure: #7b6daa;
  --syn-core: #5a87ab;
  --syn-pragma: #9a8a3a;
  --syn-magic: #b87a4a;
}

*, *::before, *::after { box-sizing: border-box; }

body {
  margin: 0;
  padding: 0;
  font-family: var(--font-body);
  font-size: var(--font-size-base);
  color: var(--fg);
  background: var(--bg);
  background-image: radial-gradient(
    ellipse at 50% 0%, var(--bg-alt) 0%, var(--bg) 70%);
  line-height: 1.5;
}

a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }
a:visited { color: var(--link-visited); }

/* --- Header bar --- */

.header {
  background: var(--header-bg);
  border-bottom: 1px solid var(--border);
  padding: 12px 24px;
  position: sticky;
  top: 0;
  z-index: 10;
}

.header-inner {
  max-width: 1400px;
  margin: 0 auto;
  display: flex;
  align-items: center;
  gap: 24px;
  flex-wrap: wrap;
}

.header h1 {
  margin: 0;
  font-size: 18px;
  font-weight: 700;
  letter-spacing: -0.02em;
  background: none;
  border: none;
  padding: 0;
  text-align: left;
}

.header-stats {
  display: flex;
  gap: 16px;
  align-items: center;
  flex-wrap: wrap;
}

.stat-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: var(--font-size-small);
  padding: 2px 8px;
  border-radius: 4px;
  border: 1px solid;
  transition: opacity 0.15s ease;
}

.stat-badge:hover { opacity: 0.85; }

.theme-toggle {
  margin-left: auto;
  background: none;
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 4px 8px;
  cursor: pointer;
  color: var(--fg);
  font-size: var(--font-size-small);
  transition: background 0.15s ease, border-color 0.15s ease;
}

.theme-toggle:hover { background: var(--bg-alt); }

/* --- Coverage classes --- */

.c0 {
  background: var(--cov-none-bg);
  border-color: var(--cov-none-border);
  color: var(--cov-none-fg);
}
.c1 {
  background: var(--cov-low-bg);
  border-color: var(--cov-low-border);
  color: var(--cov-low-fg);
}
.c2 {
  background: var(--cov-good-bg);
  border-color: var(--cov-good-border);
  color: var(--cov-good-fg);
}
.c3 {
  background: var(--cov-full-bg);
  border-color: var(--cov-full-border);
  color: var(--cov-full-fg);
}

/* --- Main content --- */

.content {
  max-width: 1400px;
  margin: 0 auto;
  padding: 16px 24px;
}

/* --- Worst files --- */

.worst-files {
  margin-bottom: 24px;
}

.worst-files h2 {
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  margin: 0 0 8px 0;
  color: var(--fg-muted);
}

.worst-list {
  display: flex;
  gap: 8px;
  flex-wrap: nowrap;
  overflow: hidden;
}

.worst-item {
  padding: 6px 12px;
  border-radius: 4px;
  border: 1px solid;
  font-size: var(--font-size-small);
  transition: opacity 0.15s ease;
}

.worst-item:hover { opacity: 0.85; }

.worst-item a { color: inherit; }

/* --- Filter bar --- */

.filter-bar {
  display: flex;
  gap: 16px;
  align-items: center;
  margin-bottom: 12px;
  flex-wrap: wrap;
}

.filter-input {
  padding: 4px 10px;
  border: 1px solid var(--border);
  border-radius: 4px;
  font-size: var(--font-size-small);
  background: var(--bg);
  color: var(--fg);
  min-width: 200px;
  transition: border-color 0.15s ease, outline 0.15s ease;
}

.filter-input:focus {
  outline: 2px solid var(--link);
  outline-offset: -1px;
}

.filter-check {
  font-size: var(--font-size-small);
  color: var(--fg-muted);
  cursor: pointer;
  user-select: none;
  display: flex;
  align-items: center;
  gap: 4px;
}

/* --- File table --- */

.file-table {
  width: 100%;
  border-collapse: collapse;
  font-size: var(--font-size-small);
}

.file-table th {
  background: var(--header-bg);
  border: 1px solid var(--border);
  padding: 6px 10px;
  text-align: center;
  font-weight: 600;
  cursor: pointer;
  user-select: none;
  white-space: nowrap;
}

.file-table th:first-child { text-align: left; }
.file-table th:hover { background: var(--border); }

.file-table td {
  border: 1px solid var(--border);
  padding: 4px 10px;
  text-align: center;
}

.file-table td:first-child { text-align: left; }

.file-table tr { transition: background 0.15s ease; }
.file-table tr:hover { background: var(--bg-alt); }

.file-table .sort-asc::after { content: " \25b2"; }
.file-table .sort-desc::after { content: " \25bc"; }

.dir-header {
  cursor: pointer;
  user-select: none;
}

.dir-header td:first-child {
  font-weight: 600;
  color: var(--fg-muted);
}

.dir-header td:first-child::before {
  content: "\25be ";
  font-size: 10px;
}

.dir-header.collapsed td:first-child::before {
  content: "\25b8 ";
}

.dir-file-grouped td:first-child {
  padding-left: 24px !important;
}

/* --- Coverage bar --- */

.cov-bar {
  display: inline-block;
  width: 50px;
  height: 8px;
  background: var(--cov-none-border);
  border-radius: 4px;
  vertical-align: middle;
  margin-left: 4px;
  overflow: hidden;
  box-shadow: inset 0 1px 2px rgba(0,0,0,0.15);
}

.cov-bar-fill {
  display: block;
  height: 100%;
  background: var(--cov-full-border);
  border-radius: 4px;
}

/* --- Source view --- */

.source-table {
  width: 100%;
  border-collapse: collapse;
  font-family: var(--font-code);
  font-size: var(--font-size-code);
  line-height: 1.4;
}

.source-table td {
  padding: 0 2px;
  border: none;
  vertical-align: top;
  line-height: 1.3;
}

.source-table tr { transition: background 0.15s ease; }
.source-table tr:hover { background: var(--bg-alt); }

.ln {
  width: 1px;
  text-align: right;
  color: var(--fg-muted);
  user-select: none;
  padding-right: 8px !important;
  border-right: 1px solid var(--border);
}

.ln a { color: var(--fg-muted); }
.ln a:hover { color: var(--link); }

.count {
  width: 1px;
  text-align: right;
  padding: 0 8px !important;
  font-size: var(--font-size-small);
}

.exec-0 { background: var(--exec-none); }
.exec-partial { background: var(--exec-partial); }
.exec-covered { background: var(--exec-covered); }

.src {
  white-space: pre;
  border-left: 3px solid transparent;
  padding-left: 8px !important;
}

.src-c0 {
  border-left-color: var(--cov-none-border);
}
.src-c1 {
  border-left-color: var(--cov-low-border);
  background: var(--cov-low-bg);
}

.src-partial {
  border-left-color: var(--cov-good-border);
}

td.chevron {
  width: 1px;
  padding: 0 2px !important;
  font-size: 8px;
  color: var(--fg-muted);
}

/* --- Syntax highlighting (PPI::HTML) --- */

.comment { color: var(--syn-comment); font-style: italic; }
.keyword { color: var(--syn-keyword); }
.double, .single, .heredoc, .heredoc_content,
  .heredoc_terminator { color: var(--syn-string); }
.number { color: var(--syn-number); }
.symbol, .cast { color: var(--syn-symbol); }
.operator { color: var(--syn-operator); }
.structure { color: var(--syn-structure); }
.core { color: var(--syn-core); }
.pragma { color: var(--syn-pragma); }
.magic { color: var(--syn-magic); }
.word { color: var(--fg); }

/* --- Inline detail sections --- */

.has-detail { cursor: pointer; }
.has-detail:hover { background: var(--bg-alt); }

.detail {
  background: var(--bg-alt);
  border: 1px solid var(--border);
  border-radius: 4px;
  margin: 4px 0 4px 40px;
  padding: 8px 12px;
  font-family: var(--font-code);
  font-size: var(--font-size-small);
}

.detail-heading {
  font-weight: 600;
  color: var(--fg-muted);
}

.detail table {
  border-collapse: collapse;
  margin-top: 4px;
}

.detail th, .detail td {
  border: 1px solid var(--border);
  padding: 2px 8px;
  text-align: center;
  font-size: var(--font-size-small);
}

.detail th { background: var(--header-bg); }
.detail .c0 { background: var(--exec-none); }
.detail .c3 { background: var(--exec-covered); }

/* --- Minimap --- */

.minimap {
  position: fixed;
  right: 0;
  top: 60px;
  bottom: 40px;
  width: 14px;
  z-index: 5;
  background: var(--bg-alt);
  border-left: 1px solid var(--border);
}

.minimap canvas { display: block; }

/* --- Distribution bar --- */

.dist-bar {
  display: flex;
  height: 12px;
  border-radius: 3px;
  overflow: hidden;
  margin-bottom: 16px;
  border: 1px solid var(--border);
}

.dist-bar-seg {
  height: 100%;
  position: relative;
}

.dist-bar-seg[title]:hover { opacity: 0.8; }

.dist-legend {
  display: flex;
  gap: 12px;
  margin-bottom: 16px;
  font-size: var(--font-size-small);
  color: var(--fg-muted);
}

.dist-legend span::before {
  content: "";
  display: inline-block;
  width: 10px;
  height: 10px;
  border-radius: 2px;
  margin-right: 4px;
  vertical-align: middle;
}

.dist-legend .leg-c0::before { background: var(--cov-none-border); }
.dist-legend .leg-c1::before { background: var(--cov-low-border); }
.dist-legend .leg-c2::before { background: var(--cov-good-border); }
.dist-legend .leg-c3::before { background: var(--cov-full-border); }

/* --- Nav links --- */

.file-nav {
  display: flex;
  justify-content: space-between;
  padding: 8px 0;
  font-size: var(--font-size-small);
}

/* --- Footer --- */

.footer {
  text-align: center;
  padding: 24px;
  font-size: var(--font-size-small);
  color: var(--fg-muted);
  border-top: 1px solid var(--border);
  margin-top: 24px;
}
CSS

$Assets{js} = <<'JS';
/* Devel::Cover Html_crisp report - progressive enhancement */
(function() {
  "use strict";

  /* --- Per-report localStorage helpers --- */
  var body = document.body;
  var rid = body.getAttribute("data-report-id") || "";
  var fileCount = parseInt(body.getAttribute("data-file-count") || "0", 10);

  function rget(key, fallback) {
    var v = localStorage.getItem("dc:" + rid + ":" + key);
    return v !== null ? v : fallback;
  }
  function rset(key, val) {
    localStorage.setItem("dc:" + rid + ":" + key, val);
  }

  /* --- Theme toggle (global, not per-report) --- */
  var toggle = document.querySelector(".theme-toggle");
  if (toggle) {
    var stored = localStorage.getItem("dc-theme");
    if (stored) document.documentElement.setAttribute("data-theme", stored);
    toggle.addEventListener("click", function() {
      var current = document.documentElement.getAttribute("data-theme");
      var isDark = current === "dark" ||
        (!current && window.matchMedia("(prefers-color-scheme: dark)").matches);
      var next = isDark ? "light" : "dark";
      document.documentElement.setAttribute("data-theme", next);
      localStorage.setItem("dc-theme", next);
      toggle.textContent = next === "dark" ? "\u2600" : "\u263e";
    });
    var isDark = stored === "dark" ||
      (!stored && window.matchMedia("(prefers-color-scheme: dark)").matches);
    toggle.textContent = isDark ? "\u2600" : "\u263e";
  }

  /* --- Index page table (sort, filter, group) --- */
  var table = document.querySelector(".file-table");
  if (table) {
    var headers = table.querySelectorAll("th[data-sort]");
    var tbody = table.querySelector("tbody");
    var filterInput = document.querySelector(".filter-input");
    var hideCovered = document.querySelector(".hide-covered");
    var groupToggle = document.querySelector(".group-toggle");

    /* --- Read persisted state --- */
    var sortCol = rget("sort-col", "total");
    var sortDir = rget("sort-dir", "asc");

    var defaultGrouped = fileCount > 30;
    var storedGrouped = rget("grouped", null);
    var isGrouped = storedGrouped !== null
      ? storedGrouped === "true"
      : defaultGrouped;

    if (filterInput)
      filterInput.value = rget("filter", "");
    if (hideCovered)
      hideCovered.checked = rget("hide-covered", "false") === "true";
    if (groupToggle)
      groupToggle.checked = isGrouped;

    /* --- Render: applies grouping, sort, filter in order --- */
    function render() {
      var grouped = groupToggle && groupToggle.checked;
      var filterText = filterInput ? filterInput.value : "";
      var hide = hideCovered ? hideCovered.checked : false;
      var re;
      try { re = new RegExp(filterText, "i"); }
      catch(e) { re = null; }

      /* 1. Grouping: show/hide headers, swap names */
      tbody.querySelectorAll(".dir-header").forEach(
        function(dh) {
          dh.style.display = grouped ? "" : "none";
          dh.classList.remove("collapsed");
        }
      );
      tbody.querySelectorAll(".dir-file").forEach(
        function(row) {
          var cell = row.children[0];
          var a = cell.querySelector("a");
          var name = cell.getAttribute("data-value");
          var base = name.replace(/.*\//, "");
          if (a) a.textContent = grouped ? base : name;
          else cell.textContent = grouped ? base : name;
          row.classList.toggle("dir-file-grouped", grouped);
          row.hidden = false;
          row.style.display = "";
        }
      );

      /* 2. Re-establish DOM order and sort */
      var sortIdx = -1;
      headers.forEach(function(h, i) {
        if (h.getAttribute("data-sort") === sortCol)
          sortIdx = i;
        h.classList.remove("sort-asc", "sort-desc");
      });

      function cmp(a, b) {
        if (sortIdx < 0) return 0;
        var av = a.children[sortIdx]
          .getAttribute("data-value");
        var bv = b.children[sortIdx]
          .getAttribute("data-value");
        var an = parseFloat(av);
        var bn = parseFloat(bv);
        var c = (isNaN(an) || isNaN(bn))
          ? (av || "").localeCompare(bv || "")
          : an - bn;
        return sortDir === "desc" ? -c : c;
      }

      if (sortIdx >= 0)
        headers[sortIdx].classList.add("sort-" + sortDir);

      if (grouped) {
        /* Move each file row after its dir-header */
        var dirMap = {};
        tbody.querySelectorAll(".dir-header").forEach(
          function(dh) {
            dirMap[dh.getAttribute("data-dir")] = dh;
          }
        );
        var files = Array.prototype.slice.call(
          tbody.querySelectorAll(".dir-file")
        );
        /* Group files by dir, sort within each group */
        var byDir = {};
        files.forEach(function(f) {
          var d = f.getAttribute("data-dir");
          if (!byDir[d]) byDir[d] = [];
          byDir[d].push(f);
        });
        Object.keys(dirMap).forEach(function(d) {
          var group = byDir[d] || [];
          group.sort(cmp);
          var dh = dirMap[d];
          var after = dh;
          group.forEach(function(f) {
            after.parentNode.insertBefore(f, after.nextSibling);
            after = f;
          });
        });
      } else {
        var all = Array.prototype.slice.call(
          tbody.querySelectorAll(".dir-file")
        );
        all.sort(cmp);
        all.forEach(function(r) { tbody.appendChild(r); });
      }

      /* 3. Filter */
      tbody.querySelectorAll(".dir-file").forEach(
        function(row) {
          var name = row.children[0]
            .getAttribute("data-value") || "";
          var cells = row.children;
          var tv = cells[cells.length - 2];
          var total = parseFloat(
            tv.getAttribute("data-value"));
          var show = (!re || re.test(name))
            && (!hide || total < 100);
          row.style.display = show ? "" : "none";
        }
      );

      /* Hide empty dir headers after filtering */
      if (grouped) {
        tbody.querySelectorAll(".dir-header").forEach(
          function(dh) {
            var hasVisible = false;
            var sib = dh.nextElementSibling;
            while (sib && sib.classList.contains("dir-file")) {
              if (sib.style.display !== "none")
                hasVisible = true;
              sib = sib.nextElementSibling;
            }
            dh.style.display = hasVisible ? "" : "none";
          }
        );
      }
    }

    /* --- Save state and re-render on changes --- */
    headers.forEach(function(h) {
      h.addEventListener("click", function() {
        var col = h.getAttribute("data-sort");
        if (sortCol === col) {
          sortDir = sortDir === "asc" ? "desc" : "asc";
        } else {
          sortCol = col;
          sortDir = "asc";
        }
        rset("sort-col", sortCol);
        rset("sort-dir", sortDir);
        render();
      });
    });

    if (filterInput) {
      filterInput.addEventListener("input", function() {
        rset("filter", filterInput.value);
        try {
          new RegExp(filterInput.value);
          filterInput.style.borderColor = "";
        } catch(e) {
          filterInput.style.borderColor =
            "var(--cov-none-border)";
        }
        render();
      });
    }

    if (hideCovered) {
      hideCovered.addEventListener("change", function() {
        rset("hide-covered", hideCovered.checked);
        render();
      });
    }

    if (groupToggle) {
      groupToggle.addEventListener("change", function() {
        rset("grouped", groupToggle.checked);
        render();
      });
    }

    /* Directory collapse/expand */
    tbody.addEventListener("click", function(e) {
      var dh = e.target.closest(".dir-header");
      if (!dh) return;
      var collapsed = dh.classList.toggle("collapsed");
      var sib = dh.nextElementSibling;
      while (sib && sib.classList.contains("dir-file")) {
        sib.hidden = collapsed;
        sib = sib.nextElementSibling;
      }
    });

    /* Initial render */
    render();
  }

  /* --- Line detail expand/collapse (source view) --- */
  var sourceTable = document.querySelector(".source-table");
  if (sourceTable) {
    var details = sourceTable.querySelectorAll(".line-detail");
    details.forEach(function(d) { d.hidden = true; });

    sourceTable.querySelectorAll(".has-detail").forEach(
      function(row) {
        row.addEventListener("click", function() {
          var d = row.nextElementSibling;
          if (d && d.classList.contains("line-detail")) {
            d.hidden = !d.hidden;
            var ch = row.querySelector("td.chevron");
            if (ch) ch.textContent = d.hidden ? "\u25b6" : "\u25bc";
          }
        });
      }
    );

    /* --- Keyboard navigation --- */
    var uncovered = document.querySelectorAll(
      "tr[data-cov='0'], tr[data-cov='2']");
    var currentIdx = -1;

    function jumpTo(idx) {
      if (idx < 0 || idx >= uncovered.length) return;
      currentIdx = idx;
      var el = uncovered[idx];
      el.scrollIntoView({ behavior: "smooth", block: "center" });
      el.style.outline = "2px solid var(--link)";
      setTimeout(function() { el.style.outline = ""; }, 1500);
    }

    document.addEventListener("keydown", function(e) {
      var tag = e.target.tagName;
      if (tag === "INPUT" || tag === "TEXTAREA") return;
      var len = uncovered.length;
      if (e.key === "j") {
        jumpTo(currentIdx + 1 < len ? currentIdx + 1 : 0);
      } else if (e.key === "k") {
        jumpTo(currentIdx > 0 ? currentIdx - 1 : len - 1);
      }
      else if (e.key === "[") {
        var prev = document.querySelector(".nav-prev");
        if (prev) window.location = prev.href;
      }
      else if (e.key === "]") {
        var next = document.querySelector(".nav-next");
        if (next) window.location = next.href;
      }
      else if (e.key === "?") {
        var help = document.querySelector(".help-overlay");
        if (help) help.hidden = !help.hidden;
      }
    });

    /* --- Scroll minimap --- */
    var minimap = document.querySelector(".minimap");
    if (minimap) {
      var canvas = document.createElement("canvas");
      var allRows = sourceTable.querySelectorAll("tr[role='row']");
      var totalLines = allRows.length;
      canvas.width = 12;
      var mmHeight = function() {
        return minimap.clientHeight;
      };
      canvas.height = mmHeight();
      minimap.appendChild(canvas);
      var ctx = canvas.getContext("2d");
      var cs = getComputedStyle(document.documentElement);

      function gp(n) {
        return cs.getPropertyValue(n).trim();
      }

      function drawMinimap() {
        var h = canvas.height;
        ctx.clearRect(0, 0, 12, h);
        var scale = h / totalLines;
        for (var i = 0; i < totalLines; i++) {
          var cov = allRows[i].getAttribute("data-cov");
          if (cov === "0")
            ctx.fillStyle = gp("--cov-none-border");
          else if (cov === "2")
            ctx.fillStyle = gp("--cov-good-border");
          else if (cov === "1")
            ctx.fillStyle = gp("--cov-full-border");
          else continue;
          var y = Math.floor(i * scale);
          ctx.fillRect(0, y, 12, Math.max(1, Math.ceil(scale)));
        }
      }

      drawMinimap();
      window.addEventListener("resize", function() {
        canvas.height = mmHeight();
        drawMinimap();
      });

      canvas.addEventListener("click", function(e) {
        var lineIdx = Math.floor(e.offsetY / canvas.height * totalLines);
        if (lineIdx >= 0 && lineIdx < totalLines) {
          allRows[lineIdx].scrollIntoView({
            behavior: "smooth", block: "center"
          });
        }
      });
      canvas.style.cursor = "pointer";
    }
  }


})();
JS

$Templates{layout} = <<'EOT';
<!DOCTYPE html>
<html lang="en">
<!--
This file was generated by Devel::Cover Version [% R.version %]
Devel::Cover is copyright 2001-2026, Paul Johnson (paul@pjcj.net)
Devel::Cover is free. It is licensed under the same terms as Perl itself.
The latest version of Devel::Cover should be available from my homepage:
https://pjcj.net
-->
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" href="[% asset_prefix %]assets/style.css">
<link rel="icon" href="data:image/svg+xml,
  <svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'>
  <circle cx='8' cy='8' r='7' fill='[% R.favicon_colour %]'/>
  </svg>">
<title>[% title || "Coverage Report" %] - Devel::Cover</title>
</head>
<body data-report-id="[% R.report_id %]"
  data-file-count="[% R.file_count %]">
[% content %]
<div class="footer">
Generated by <a href="https://metacpan.org/pod/Devel::Cover">Devel::Cover</a>
[% R.version %] on [% R.date %] | Perl [% R.perl_v %] | [% R.os %]
</div>
<script src="[% asset_prefix %]assets/app.js"></script>
</body>
</html>
EOT

$Templates{index} = <<'EOT';
[% WRAPPER layout asset_prefix="" title="Coverage Summary" %]

<div class="header">
<div class="header-inner">
<h1>Coverage Report</h1>
<div class="header-stats">
[% IF total.total.pc != "n/a" %]
<span class="stat-badge [% total.total.class %]"
      title="[% total.total.covered %] / [% total.total.total %]">
Total: [% total.total.pc %]%
<span class="cov-bar">
<span class="cov-bar-fill"
  style="width:[% total.total.pc %]%"></span>
</span>
</span>
[% END %]
[% FOREACH c = R.showing %]
[% s = total.$c %]
[% NEXT IF c == "time" %]
[% NEXT UNLESS s.pc %]
<span class="stat-badge [% s.class %]"
      title="[% c %]: [% s.covered %] / [% s.total %]">
[% c %] [% s.pc %]%
</span>
[% END %]
</div>
<button class="theme-toggle" aria-label="Toggle dark mode">&#x263e;</button>
</div>
</div>

<div class="content">

[% IF worst.size > 0 %][% IF worst.0.risk > 0 %]
<div class="worst-files">
<h2>Highest risk</h2>
<div class="worst-list">
[% FOREACH f = worst %]
[% NEXT IF f.risk == 0 %]
<div class="worst-item [% f.total.class %]">
[% IF f.exists %]
<a href="[% f.link %]">[% f.name %]</a>
[% ELSE %][% f.name %][% END %]
<strong>[% f.risk | format('%d') %]</strong>
</div>
[% END %]
</div>
</div>
[% END %][% END %]

[% IF dist_total > 0 %]
<div class="dist-bar">
[% IF dist.c0 %]
<div class="dist-bar-seg"
  style="width:[% dist.c0 / dist_total * 100 %]%;
    background:var(--cov-none-border)"
  title="[% dist.c0 %] files &lt; [% R.threshold.c0 %]%">
</div>
[% END %]
[% IF dist.c1 %]
<div class="dist-bar-seg"
  style="width:[% dist.c1 / dist_total * 100 %]%;
    background:var(--cov-low-border)"
  title="[% dist.c1 %] files [% R.threshold.c0 %]-[% R.threshold.c1 %]%">
</div>
[% END %]
[% IF dist.c2 %]
<div class="dist-bar-seg"
  style="width:[% dist.c2 / dist_total * 100 %]%;
    background:var(--cov-good-border)"
  title="[% dist.c2 %] files [% R.threshold.c1 %]-100%">
</div>
[% END %]
[% IF dist.c3 %]
<div class="dist-bar-seg"
  style="width:[% dist.c3 / dist_total * 100 %]%;
    background:var(--cov-full-border)"
  title="[% dist.c3 %] files 100%">
</div>
[% END %]
</div>
<div class="dist-legend">
<span class="leg-c0">[% dist.c0 %] &lt; [% R.threshold.c0 %]%</span>
<span class="leg-c1">
[% dist.c1 %] [% R.threshold.c0 %]-[% R.threshold.c1 %]%
</span>
<span class="leg-c2">[% dist.c2 %] [% R.threshold.c1 %]-100%</span>
<span class="leg-c3">[% dist.c3 %] at 100%</span>
</div>
[% END %]

<div class="filter-bar">
<input type="text" class="filter-input"
  placeholder="Filter files (regex)..."
  aria-label="Filter files">
<label class="filter-check">
<input type="checkbox" class="hide-covered">
Hide 100% covered</label>
<label class="filter-check">
<input type="checkbox" class="group-toggle">
Group by directory</label>
</div>

<table class="file-table">
<thead>
<tr>
<th data-sort="file">File</th>
[% FOREACH c = R.showing %]
[% NEXT IF c == "time" %]
<th data-sort="[% c %]">[% c %]</th>
[% END %]
<th data-sort="total">Total</th>
<th data-sort="risk">Risk</th>
</tr>
</thead>
<tbody>
[% FOREACH g = groups %]
<tr class="dir-header" data-dir="[% g.dir %]">
<td>[% g.dir %]</td>
[% FOREACH c = R.showing %]
[% NEXT IF c == "time" %]
<td></td>
[% END %]
<td class="[% g.class %]">
[% g.pc %]
[% IF g.pc != 'n/a' %]
<span class="cov-bar">
<span class="cov-bar-fill"
  style="width:[% g.pc %]%"></span>
</span>
[% END %]
</td>
<td></td>
</tr>
[% FOREACH f = g.files %]
<tr class="dir-file" data-dir="[% g.dir %]">
<td data-value="[% f.name %]">
[% IF f.exists %]
<a href="[% f.link %]">[% f.basename %]</a>
[% ELSE %][% f.basename %][% END %]
</td>
[% FOREACH c = R.showing %]
[% NEXT IF c == "time" %]
[% s = f.criteria.$c %]
<td class="[% s.class %]"
    data-value="[% s.pc == 'n/a' ? -1 : s.pc %]"
    title="[% s.covered %] / [% s.total %]">
[% s.pc %]
[% IF s.pc != 'n/a' %]
<span class="cov-bar">
<span class="cov-bar-fill"
  style="width:[% s.pc %]%"></span>
</span>
[% END %]
</td>
[% END %]
<td class="[% f.total.class %]"
    data-value="[% f.total_sort %]"
    title="[% f.total.covered %] / [% f.total.total %]">
[% f.total.pc %]
[% IF f.total.pc != 'n/a' %]
<span class="cov-bar">
<span class="cov-bar-fill"
  style="width:[% f.total.pc %]%"></span>
</span>
[% END %]
</td>
<td data-value="[% f.risk %]">
[% f.risk | format('%d') %]</td>
</tr>
[% END %]
[% END %]
</tbody>
</table>

</div>
[% END %]
EOT

$Templates{file} = <<'EOT';
[% WRAPPER layout asset_prefix="" title=file.name %]

<div class="header">
<div class="header-inner">
<h1>[% file.name %]</h1>
<div class="header-stats">
[% FOREACH c = R.showing %]
[% NEXT IF c == "time" %]
[% s = total.$c %]
[% NEXT UNLESS s.pc AND s.pc != 'n/a' %]
<span class="stat-badge [% s.class %]"
      title="[% c %]: [% s.covered %] / [% s.total %]">
[% c %] [% s.pc %]%
</span>
[% END %]
</div>
<button class="theme-toggle" aria-label="Toggle dark mode">&#x263e;</button>
</div>
</div>

<div class="content">

<div class="file-nav">
<span>
[% IF prev_file %]
<a href="[% prev_file.link %]" class="nav-prev">&laquo; [% prev_file.name %]</a>
[% END %]
</span>
<span><a href="index.html">&uarr; Summary</a></span>
<span>
[% IF next_file %]
<a href="[% next_file.link %]" class="nav-next">[% next_file.name %] &raquo;</a>
[% END %]
</span>
</div>

<div class="minimap"></div>
<table class="source-table" role="table"
  aria-label="Coverage for [% file.name %]">
[% FOREACH line = lines %]
[% SET cov_defined = line.count.defined %]
[% SET is_uncov = cov_defined AND line.count == 0
    AND line.count_class == 'c0' %]
[% SET has_detail = line.branches
    || line.truth_tables
    || line.subroutines
    || line.pod %]
<tr role="row"
    [% IF cov_defined -%]
    data-cov="[% IF line.count == 0 %]0
      [%- ELSIF line.partial %]2[% ELSE %]1[% END %]"
    [%- END %]
    class="[% IF is_uncov %]src-c0[% END -%]
      [%- IF has_detail %] has-detail[% END %]">
<td role="cell" class="ln">
<a id="L[% line.number %]"
  href="#L[% line.number %]">[% line.number %]</a>
</td>
<td role="cell"
    class="count [%- IF line.partial %]exec-partial
      [%- ELSE %][% line.exec_class -%]
      [%- IF line.pod_uncovered %] c0[% END -%]
      [%- END %]"
    aria-label="[% IF cov_defined -%]
      executed [% line.count %] times
      [%- ELSE -%]
      no coverage data[% END %]">
[% IF cov_defined %][% line.count %][% END %]
</td>
<td role="cell" class="chevron">[%- IF has_detail %]&#x25b6;[% END -%]</td>
<td role="cell" class="src
    [%- IF is_uncov %] src-c0[% END -%]
    [%- IF line.partial %] src-partial[% END -%]
    [%- IF line.count_class == 'c1' %] src-c1[% END -%]
">[% line.text %]</td>
</tr>

[% IF has_detail %]
<tr class="line-detail"><td colspan="4">
[% IF line.subroutines %]
[% FOREACH s = line.subroutines %]
<div class="detail">
<span class="detail-heading">Subroutine</span>
<span class="[% s.class %]">
[% s.name %]:
[% IF s.covered %]called[% ELSE %]not called[% END %]
</span>
</div>
[% END %]
[% END %]
[% IF line.pod %]
[% FOREACH p = line.pod %]
<div class="detail">
<span class="detail-heading">Pod</span>
<span class="[% p.class %]">
[% IF p.covered %]documented[% ELSE %]undocumented[% END %]
</span>
</div>
[% END %]
[% END %]
[% IF line.branches %]
<div class="detail">
<span class="detail-heading">
Branch: [% line.branches.size %]
branch[% IF line.branches.size > 1 %]es[% END %]
</span>
<table>
<tr><th>Branch</th><th>True</th><th>False</th></tr>
[% FOREACH b = line.branches %]
<tr>
<td>[% b.text %]</td>
<td class="[% b.true_class %]">[% b.true_count %]</td>
<td class="[% b.false_class %]">[% b.false_count %]</td>
</tr>
[% END %]
</table>
</div>
[% END %]
[% IF line.truth_tables %]
[% FOREACH tt = line.truth_tables %]
<div class="detail">
<span class="detail-heading">
Condition: [% tt.expr %]
</span>
<table>
<tr>
[% FOREACH h = tt.headers %]<th>[% h %]</th>[% END %]
<th>result</th>
</tr>
[% FOREACH row = tt.rows %]
<tr class="[% row.class %]">
[% FOREACH i = row.inputs %]<td>[% i %]</td>[% END %]
<td>[% row.result %]</td>
</tr>
[% END %]
</table>
</div>
[% END %]
[% END %]
</td></tr>
[% END %]

[% END %]
</table>

<div class="file-nav">
<span>
[% IF prev_file %]
<a href="[% prev_file.link %]" class="nav-prev">&laquo; [% prev_file.name %]</a>
[% END %]
</span>
<span><a href="index.html">&uarr; Summary</a></span>
<span>
[% IF next_file %]
<a href="[% next_file.link %]" class="nav-next">[% next_file.name %] &raquo;</a>
[% END %]
</span>
</div>

<div class="help-overlay" hidden>
<h3>Keyboard shortcuts</h3>
<table>
<tr><td><kbd>j</kbd></td><td>Next uncovered/partial line</td></tr>
<tr><td><kbd>k</kbd></td><td>Previous uncovered/partial line</td></tr>
<tr><td><kbd>[</kbd></td><td>Previous file</td></tr>
<tr><td><kbd>]</kbd></td><td>Next file</td></tr>
<tr><td><kbd>?</kbd></td><td>Toggle this help</td></tr>
</table>
</div>

</div>
[% END %]
EOT

# Remove leading whitespace from templates
s/^\s+//gm for values %Templates;

package Devel::Cover::Report::Html_crisp::Template::Provider;

use v5.20.0;
use strict;
use warnings;
use feature "signatures";
no warnings "experimental::signatures";

# VERSION

use base "Template::Provider";

sub fetch ($self, $name, @rest) {
  my $t = \%Devel::Cover::Report::Html_crisp::Templates;
  $self->SUPER::fetch((exists $t->{$name} ? \$t->{$name} : $name), @rest)
}

"
And when he shall die,
Take him and cut him out in little stars,
And he will make the face of heaven so fine
That all the world will be in love with night
And pay no worship to the garish sun.
"

__END__

=head1 NAME

Devel::Cover::Report::Html_crisp - Modern HTML backend for Devel::Cover

=head1 SYNOPSIS

 cover -report html_crisp

=head1 DESCRIPTION

This module provides a modern HTML reporting mechanism for coverage data. It
generates a single-page dashboard with file listing and per-file source views
with inline branch, condition, and subroutine detail.

Features include dark mode support, keyboard navigation, sortable columns, and
inline condition truth tables.

It is designed to be called from the C<cover> program.  It will add syntax
highlighting if C<PPI::HTML> or C<Perl::Tidy> is installed.

=head1 OPTIONS

The following command line options are supported:

 -outputfile  - name of output file              (default index.html)
 -noppihtml   - disables PPI::HTML highlighting  (default off)
 -noperltidy  - disables Perl::Tidy highlighting (default off)

=head1 SEE ALSO

 Devel::Cover

=head1 LICENCE

Copyright 2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

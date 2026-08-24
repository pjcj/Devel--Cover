#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( diag done_testing is is_deeply like )];
use Devel::Cover::Branch              ();  ## no perlimports
use Devel::Cover::Condition_and_2     ();  ## no perlimports
use Devel::Cover::Mcdc                ();  ## no perlimports
use Devel::Cover::Pod                 ();  ## no perlimports
use Devel::Cover::Report::Compilation ();
use Devel::Cover::Statement           ();  ## no perlimports
use Devel::Cover::Subroutine          ();  ## no perlimports
use Devel::Cover::Test::Showcase      qw(
  create_cover_db
  run_cover
  setup_lib_dir
);

# The compilation reporter emits one line per uncovered location in a format
# similar to Perl's own compilation errors, so editors with a quickfix-style
# error navigator can step through them.
sub test_compilation_report () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "compilation",
    "--silent",     $cover_db,
  );

  is $exit, 0, "cover --report compilation exits 0" or diag $out;

  like $out, qr/Uncovered statement at .* line \d+/,
    "uncovered statement line emitted";
  like $out, qr/Uncovered subroutine \S+ at .* line \d+/,
    "uncovered subroutine line emitted";
  like $out, qr|Uncovered MC/DC pair \([^)]*\) at .* line \d+: .+|,
    "uncovered MC/DC pair line emitted";

  my %stmt_lines;
  while ($out =~ /^Uncovered statement at (\S+) line (\d+)$/gm) {
    push $stmt_lines{$1}->@*, $2;
  }
  for my $file (sort keys %stmt_lines) {
    is_deeply $stmt_lines{$file}, [sort { $a <=> $b } $stmt_lines{$file}->@*],
      "statement lines ascending for $file";
  }
}

{

  package Mock::Item;
  sub new            ($class) { bless {}, $class }
  sub covered        ($self)  { 0 }
  sub uncoverable    ($self)  { 0 }
  sub error          ($self)  { 1 }
  sub coverage_state ($self)  { "uncovered" }
  sub name           ($self)  { "mock_sub" }
}

{

  package Mock::Criterion;
  sub new ($class, @locations) { bless { locations => \@locations }, $class }

  sub items ($self) {
    my %seen;
    grep !$seen{$_}++, map $_->[0], $self->{locations}->@*
  }

  sub location ($self, $loc) {
    [map $_->[1], grep { $_->[0] == $loc } $self->{locations}->@*]
  }
}

{

  package Mock::File;
  sub new        ($class, $crit) { bless { crit => $crit }, $class }
  sub statement  ($self)         { $self->{crit} }
  sub branch     ($self)         { $self->{crit} }
  sub condition  ($self)         { $self->{crit} }
  sub mcdc       ($self)         { $self->{crit} }
  sub subroutine ($self)         { $self->{crit} }
  sub pod        ($self)         { $self->{crit} }
}

{

  package Mock::Cover;
  sub new  ($class, $file) { bless { file => $file }, $class }
  sub file ($self, $name)  { $self->{file} }
}

{

  package Mock::DB;
  sub new   ($class, $cover) { bless { cover => $cover }, $class }
  sub cover ($self)          { $self->{cover} }
}

sub capture_output ($print_sub, $crit) {
  my $db = Mock::DB->new(Mock::Cover->new(Mock::File->new($crit)));
  my $output;
  {
    open my $fh, ">", \$output or die "Cannot open scalar ref: $!";
    local *STDOUT = $fh;
    $print_sub->($db, "Mock.pm", {});
    close $fh or die "Cannot close scalar ref: $!";
  }
  $output // ""
}

sub capture_lines ($print_sub) {
  my $crit = Mock::Criterion->new(map [$_, Mock::Item->new], 10, 2, 19, 7, 13);
  [capture_output($print_sub, $crit) =~ /line (\d+)$/gm]
}

# Hash order can coincidentally ascend, so feed a fixed non-ascending order.
sub test_lines_sorted () {
  my %print = (
    statement  => \&Devel::Cover::Report::Compilation::print_statement,
    subroutine => \&Devel::Cover::Report::Compilation::print_subroutines,
    pod        => \&Devel::Cover::Report::Compilation::print_pod,
  );
  for my $criterion (sort keys %print) {
    my $lines = capture_lines($print{$criterion});
    is_deeply $lines, [2, 7, 10, 13, 19],
      "$criterion lines emitted in ascending order";
  }
}

sub stmt_obj ($covered, $uncoverable = 0) {
  bless [$covered, $uncoverable], "Devel::Cover::Statement"
}

sub sub_obj ($covered, $name, $uncoverable = 0) {
  bless [$covered, $name, $uncoverable], "Devel::Cover::Subroutine"
}

sub pod_obj ($covered, $uncoverable = 0) {
  bless [$covered, undef, $uncoverable], "Devel::Cover::Pod"
}

sub branch_obj ($text, $values, $uncoverable = undef) {
  bless [$values, { text => $text }, $uncoverable // [0, 0]],
    "Devel::Cover::Branch"
}

sub cond_obj ($left, $right, $values, $uncoverable = undef) {
  bless [
    $values,
    { left => $left, op => "&&", right => $right, type => "and_2" },
    $uncoverable // [0, 0],
    ],
    "Devel::Cover::Condition_and_2"
}

sub mcdc_obj ($text, $values, $uncoverable = undef) {
  bless [
    $values,
    { text => $text, labels => ["a", "b"] },
    $uncoverable // [0, 0],
    ],
    "Devel::Cover::Mcdc"
}

sub lines (@lines) { join "", map "$_\n", @lines }

# Each criterion has four states per construct: covered, uncovered, excused
# (uncovered but marked uncoverable) and stale (covered but marked
# uncoverable). Only uncovered and stale are errors and only they are
# reported.
sub test_statement_states () {
  my $crit = Mock::Criterion->new(
    [1, stmt_obj(1)],
    [2, stmt_obj(0)],
    [3, stmt_obj(0, 1)],
    [4, stmt_obj(1, 1)],
  );
  is capture_output(\&Devel::Cover::Report::Compilation::print_statement,
    $crit),
    lines(
      "Uncovered statement at Mock.pm line 2",
      "Statement marked uncoverable but covered at Mock.pm line 4",
    ),
    "statement reports uncovered and stale, skips covered and excused";
}

sub test_subroutine_states () {
  my $crit = Mock::Criterion->new(
    [1, sub_obj(1, "alpha")],
    [2, sub_obj(0, "beta")],
    [3, sub_obj(0, "gamma", 1)],
    [4, sub_obj(1, "delta", 1)],
  );
  is capture_output(
    \&Devel::Cover::Report::Compilation::print_subroutines, $crit
    ),
    lines(
      "Uncovered subroutine beta at Mock.pm line 2",
      "Subroutine delta marked uncoverable but covered at Mock.pm line 4",
    ),
    "subroutine reports uncovered and stale, skips covered and excused";
}

sub test_pod_states () {
  my $crit = Mock::Criterion->new(
    [1, pod_obj(1)],
    [2, pod_obj(0)],
    [3, pod_obj(0, 1)],
    [4, pod_obj(1, 1)],
  );
  is capture_output(\&Devel::Cover::Report::Compilation::print_pod, $crit),
    lines(
      "Uncovered pod at Mock.pm line 2",
      "Pod marked uncoverable but covered at Mock.pm line 4",
    ),
    "pod reports uncovered and stale, skips covered and excused";
}

sub test_branch_states () {
  my $crit = Mock::Criterion->new(
    [1, branch_obj('if $a', [1, 1])],
    [2, branch_obj('if $b', [1, 0])],
    [3, branch_obj('if $c', [0, 0], [0, 1])],
    [4, branch_obj('if $d', [0, 0])],
    [5, branch_obj('if $e', [1, 1], [0, 1])],
    [6, branch_obj('unless $f', [0, 1])],
    [7, branch_obj('if $g', [0, 0], [1, 1])],
  );
  is capture_output(\&Devel::Cover::Report::Compilation::print_branches, $crit),
    lines(
      'Branch never false at Mock.pm line 2: $b',
      'Branch never true at Mock.pm line 3: $c',
      'Branch never reached at Mock.pm line 4: $d',
      'Branch false marked uncoverable but covered at Mock.pm line 5: $e',
      'Branch never false at Mock.pm line 6: $f',
    ),
    "branch skips excused directions and reports stale ones";
}

sub test_condition_states () {
  my $crit = Mock::Criterion->new(
    [1, cond_obj('$a', '$b', [1, 1])],
    [2, cond_obj('$c', '$d', [0, 1])],
    [3, cond_obj('$e', '$f', [0, 0], [1, 0])],
    [4, cond_obj('$g', '$h', [1, 1], [1, 0])],
    [5, cond_obj('$i', '$j', [0, 0], [1, 1])],
  );
  is capture_output(\&Devel::Cover::Report::Compilation::print_conditions,
    $crit),
    lines(
      'Uncovered condition (!l) at Mock.pm line 2: $c && $d',
      'Uncovered condition (l) at Mock.pm line 3: $e && $f',
      "Condition (!l) marked uncoverable but covered at Mock.pm line 4: "
      . '$g && $h',
    ),
    "condition names only genuinely missed outcomes and reports stale ones";
}

# Two conditions of the same type on one line each need the line number,
# since every message here is meant to be machine-navigable.
sub test_condition_repeated_location () {
  my $crit = Mock::Criterion->new(
    [2, cond_obj('$p', "1", [1, 0])],
    [2, cond_obj('$p', "2", [1, 0])],
  );
  is capture_output(\&Devel::Cover::Report::Compilation::print_conditions,
    $crit),
    lines(
      'Uncovered condition (l) at Mock.pm line 2: $p && 1',
      'Uncovered condition (l) at Mock.pm line 2: $p && 2',
    ),
    "every condition on a line carries the line number";
}

sub test_mcdc_states () {
  my $crit = Mock::Criterion->new(
    [1, mcdc_obj('$a || $b', [1, 1])],
    [2, mcdc_obj('$c || $d', [1, 0])],
    [3, mcdc_obj('$e || $f', [1, 0], [0, 1])],
    [4, mcdc_obj('$g || $h', [1, 1], [0, 1])],
    [5, mcdc_obj('$i || $j', [1, 0], [1, 0])],
  );
  is capture_output(\&Devel::Cover::Report::Compilation::print_mcdc, $crit),
    lines(
      'Uncovered MC/DC pair (b) at Mock.pm line 2: $c || $d',
      "MC/DC pair (b) marked uncoverable but covered at Mock.pm line 4: "
      . '$g || $h',
      'Uncovered MC/DC pair (b) at Mock.pm line 5: $i || $j',
      "MC/DC pair (a) marked uncoverable but covered at Mock.pm line 5: "
      . '$i || $j',
    ),
    "mcdc skips excused atomics and reports stale ones";
}

# A stale marker forgiven by -ignore_covered_err is not an error, so it
# must not be reported alongside a genuine miss on the same construct.
sub test_ignore_covered_err () {
  no warnings "once";
  local $Devel::Cover::Ignore_covered_err = 1;

  my $conds = Mock::Criterion->new([2, cond_obj('$c', '$d', [0, 1], [0, 1])]);
  is capture_output(
    \&Devel::Cover::Report::Compilation::print_conditions, $conds
    ),
    lines('Uncovered condition (!l) at Mock.pm line 2: $c && $d'),
    "forgiven stale condition outcome not reported";

  my $mcdc = Mock::Criterion->new([3, mcdc_obj('$e || $f', [0, 1], [0, 1])]);
  is capture_output(\&Devel::Cover::Report::Compilation::print_mcdc, $mcdc),
    lines('Uncovered MC/DC pair (a) at Mock.pm line 3: $e || $f'),
    "forgiven stale mcdc atomic not reported";
}

sub main () {
  test_compilation_report;
  test_lines_sorted;
  test_statement_states;
  test_subroutine_states;
  test_pod_states;
  test_branch_states;
  test_condition_states;
  test_condition_repeated_location;
  test_mcdc_states;
  test_ignore_covered_err;
  done_testing;
}

main;

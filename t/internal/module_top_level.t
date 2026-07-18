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

use Cwd        qw( realpath );
use File::Path qw( make_path );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing is ok )];

use Devel::Cover::DB ();

# The top-level statements of a required module compile into an op tree
# which perl frees as soon as the require completes.  Devel::Cover keeps
# those optrees alive from its leaveeval hook and walks them at report
# time, so top-level statements, branches and conditions are covered
# like any other code.  See docs/technical/require-toplevel-coverage.md
# for the analysis.

# Write a module and a program using it, run the program under coverage
# and return the cover object for the module's file.
sub covered_file ($name, $module, $program, $expect, $extra = {}, $opts = "") {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));

  my %write = (
    File::Spec->catfile($tmpdir, "$name.pm") => $module,
    File::Spec->catfile($tmpdir, "prog.pl")  => $program,
    map { File::Spec->catfile($tmpdir, split m{/}) => $extra->{$_} }
      keys %$extra,
  );
  for my $path (sort keys %write) {
    # keep the volume (splitpath drops it into a separate element) so the
    # directory is created on the right drive under Windows, not just its
    # path relative to the current one
    my ($vol, $dirs) = File::Spec->splitpath($path);
    make_path(File::Spec->catpath($vol, $dirs, ""));
    open my $fh, ">", $path or die "Cannot write $path: $!";
    print $fh $write{$path};
    close $fh or die "Cannot close $path: $!";
  }

  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  my $prog     = File::Spec->catfile($tmpdir, "prog.pl");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$tmpdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0"
    . ",-select,$name,-ignore,.$opts"
    . " $prog 2>&1";
  my $out = `$cmd`;
  is $?,   0,       "$name: covered run exits 0" or diag $out;
  is $out, $expect, "$name: module code ran";

  my $db     = Devel::Cover::DB->new(db => $cover_db)->merge_runs;
  my ($file) = grep m|\Q$name\E\.pm$|, $db->cover->items;
  ok $file, "$name.pm is in the coverage database" or return;
  $db->cover->file($file)
}

# A module whose top-level code contains statements, a loop and a
# conditional, all fully executed.  The line numbers of the heredoc
# content are fixed and the assertions refer to them directly.
sub test_full_execution () {
  my $f = covered_file("TopLevel", <<'PERL', <<'PROG', "14\n") or return;
package TopLevel;
use strict;
use warnings;

my $count = 0;
$count = $count + 1;
for my $i (1 .. 3) {
  $count += $i;
}
if ($count > 2) {
  $count *= 2;
}

sub get_count { $count }

1;
PERL
use TopLevel;
print TopLevel::get_count(), "\n";
PROG

  my $stmt = $f->statement;
  ok $stmt->location(14), "sub body statement is covered";
  is $stmt->location(14)->[0]->covered, 1, "sub body statement has a count";
  ok $f->subroutine->location(14), "get_count subroutine is covered";

  my %count = (5 => 1, 6 => 1, 7 => 1, 8 => 3, 10 => 1, 11 => 1);
  for my $line (sort { $a <=> $b } keys %count) {
    my $l = $stmt->location($line);
    ok $l, "top-level statement on line $line is collected";
    is $l && $l->[0]->covered, $count{$line},
      "top-level statement on line $line has count $count{$line}";
  }
  my $branch = $f->branch;
  ok $branch && $branch->location(10), "top-level branch is collected";
}

# A module whose top-level code is only partially executed.  The real
# payoff of retaining require optrees is reporting the untaken side as
# uncovered rather than omitting the whole construct.
sub test_partial_execution () {
  my $f = covered_file("TopPartial", <<'PERL', <<'PROG', "2\n") or return;
package TopPartial;

my $flag = 0;
if ($flag) {
  $flag = 42;
} else {
  $flag = 2;
}

sub get_flag { $flag }

1;
PERL
use TopPartial;
print TopPartial::get_flag(), "\n";
PROG

  my $stmt = $f->statement;
  my $l    = $stmt->location(5);
  ok $l, "unexecuted top-level statement is collected";
  is $l && $l->[0]->covered, 0, "and is reported as uncovered";
  my $taken = $stmt->location(7);
  is $taken && $taken->[0]->covered, 1, "executed else branch statement ran";
  my $branch = $f->branch;
  ok $branch && $branch->location(4), "top-level branch is collected";
}

# Anonymous subs defined at file scope.  Their prototype CVs live in the
# pad of the file's eval CV, which the leaveeval hook keeps alive, so
# the require-tree walk covers them from there.
sub test_anon_sub () {
  my $f = covered_file("TopAnon", <<'PERL', <<'PROG', "3\n7\n") or return;
package TopAnon;

my $add = sub {
  my ($x, $y) = @_;
  $x + $y
};

my $unused = sub {
  my ($x) = @_;
  $x * 2
};

my $outer = sub {
  my $inner = sub {
    my ($x) = @_;
    my $inner_inner = sub {
      my ($y) = @_;
      $y * 3
    };
    $inner_inner->($x) + 1
  };
  $inner->(2)
};

sub call_add  { $add->(1, 2) }
sub run_outer { $outer->() }

1;
PERL
use TopAnon;
print TopAnon::call_add(),  "\n";
print TopAnon::run_outer(), "\n";
PROG

  my $stmt = $f->statement;
  ok $stmt->location(25), "named sub calling the anon sub is covered";
  # The assignment statement is attributed to the closing line of the
  # anon sub because its body resets the parser's statement-start line
  ok $stmt->location(6), "anon sub assignment statement is collected";

  my $l = $stmt->location(4);
  ok $l, "file-scope anon sub body is collected";
  is $l && $l->[0]->covered, 1, "and has a count";

  my $u = $stmt->location(9);
  ok $u, "uncalled anon sub body is collected";
  is $u && $u->[0]->covered, 0, "and is reported as uncovered";

  for my $line (15, 17, 20) {
    my $n = $stmt->location($line);
    ok $n, "nested anon sub statement on line $line is collected";
    is $n && $n->[0]->covered, 1, "and has a count";
  }
}

# A selected module whose final top-level statement is a require of an
# unselected file.  The inner file's cops leave the cached collecting flag
# false, so the leaveeval hook must refresh it rather than trust the cache,
# otherwise the whole selected tree is lost.
sub test_require_unselected_last () {
  my $f = covered_file(
    "TopReq", <<'PERL', <<'PROG', "done\n",
package TopReq;

my $x = 1;
$x = $x + 1;

require Unselected::Helper;
PERL
use TopReq;
print "done\n";
PROG
    { "Unselected/Helper.pm" => <<'DEP' });
package Unselected::Helper;
my $y = 5;
1;
DEP

  my $stmt = $f->statement;
  for my $line (3, 4, 6) {
    my $l = $stmt->location($line);
    ok $l, "top-level statement on line $line is collected";
    is $l && $l->[0]->covered, 1, "and has a count";
  }
}

# A file-scope anon sub installed into a glob is reachable both from the
# symbol table (as a named glob slot) and from the husk pad.  Feeding the
# husk pad CVs through @Cvs before check_files lets the normal anon merge
# collapse the two records, so the sub is reported once, not twice.  The
# interleaved named subs push the two walks apart, which is what defeated
# the merge when the pad was walked separately in the require closure.
sub test_glob_anon_single_record () {
  my $f = covered_file("TopGlob", <<'PERL', <<'PROG', "pos\n1\n2\n") or return;
package TopGlob;

sub named_one { 1 }

*handler = sub {
  my $x = shift;
  $x > 0 ? "pos" : "neg";
};

sub named_two { 2 }

1;
PERL
use TopGlob;
print TopGlob::handler(5), "\n";
print TopGlob::named_one(), "\n";
print TopGlob::named_two(), "\n";
PROG

  my $subs = $f->subroutine;
  my $anon = $subs->location(6);
  ok $anon, "glob-installed anon sub is collected";
  is scalar @$anon, 1, "and is recorded exactly once, not duplicated";
  is $anon && $anon->[0]->name, "__ANON__", "the record is the anon sub";
}

# A module required, dropped from %INC and required again captures one
# tree per compilation.  Each tree's ops have distinct addresses, so
# without per-file suppression every top-level statement is recorded once
# per compilation.  Keeping only the latest tree collapses them to one row.
sub test_reload_single_record () {
  my $f = covered_file("TopReload", <<'PERL', <<'PROG', "2\n") or return;
package TopReload;
my $x = 1;
$x = $x + 1;
sub val { $x }
1;
PERL
require TopReload;
delete $INC{"TopReload.pm"};
require TopReload;
print TopReload::val(), "\n";
PROG

  my $stmt = $f->statement;
  for my $line (2, 3, 5) {
    my $l = $stmt->location($line);
    ok $l, "top-level statement on line $line is collected";
    is scalar @$l, 1, "and is recorded once despite the reload";
  }
}

# A module whose top-level code exits with a return.  pp_return unwinds
# the require's eval context and tail-calls pp_leaveeval directly, so the
# leaveeval op is never dispatched and the leaveeval hook cannot fire.  The
# return hook captures the tree from the unwind path instead, so the
# top-level statements are covered like any other.
sub test_top_level_return () {
  my $f = covered_file("TopReturn", <<'PERL', <<'PROG', "2\n") or return;
package TopReturn;
my $x = 1;
$x = $x + 1;
sub val { $x }
return 1;
PERL
use TopReturn;
print TopReturn::val(), "\n";
PROG

  my $stmt = $f->statement;
  for my $line (2, 3, 5) {
    my $l = $stmt->location($line);
    ok $l, "top-level statement on line $line is collected";
    is $l && $l->[0]->covered, 1, "and has a count";
  }
}

# A module whose final top-level statement sits under a #line directive
# naming another file.  The capture must identify the tree by its own
# first COP, not by PL_curcop (the last statement executed), otherwise the
# collecting check consults the fake file, rejects the whole tree and every
# top-level statement is lost.
sub test_trailing_line_directive () {
  my $f = covered_file("TopLine", <<'PERL', <<'PROG', "2\n") or return;
package TopLine;
my $x = 1;
$x = $x + 1;
sub val { $x }
#line 100 "Phantom.yp"
$x;
PERL
use TopLine;
print TopLine::val(), "\n";
PROG

  my $stmt = $f->statement;
  for my $line (2, 3) {
    my $l = $stmt->location($line);
    ok $l, "top-level statement on line $line is collected";
    is $l && $l->[0]->covered, 1, "and has a count";
  }
}

# A sub that lexically encloses a my sub compiles with an introcv/clonecv
# prologue before its first statement, so its START is not the nextstate
# COP that check_file expects and its ROOT->first->first is a nested
# lineseq wrapping the prologue rather than the first statement's COP.
# Both check_file and sub_info must step past the prologue, otherwise the
# enclosing sub is dropped from coverage entirely along with its body.
sub test_enclosing_sub () {
  my $f = covered_file("TopEnclosing", <<'PERL', <<'PROG', "25\n") or return;
package TopEnclosing;
use feature 'lexical_subs';
no warnings 'experimental::lexical_subs';

sub with_mysub {
  my sub inner { my $x = shift; $x + 5 }
  inner(shift)
}

1;
PERL
use TopEnclosing;
print TopEnclosing::with_mysub(20), "\n";
PROG

  # A sub is anchored at its first executable statement, which for the
  # enclosing sub is the inner(shift) call on line 7, not the declaration
  my $subs = $f->subroutine;
  my $sub  = $subs->location(7);
  ok $sub, "enclosing sub with_mysub is collected";
  is $sub && $sub->[0]->name,    "with_mysub", "and is the enclosing sub";
  is $sub && $sub->[0]->covered, 1,            "and is reported as covered";

  my $stmt = $f->statement;
  my $body = $stmt->location(7);
  ok $body, "enclosing sub body statement is collected";
  is $body && $body->[0]->covered, 1, "and has a count";
}

# A file loaded with do FILE rather than require or use.  do pushes an
# OP_DOFILE eval context, not OP_REQUIRE, so the capture guard must accept
# it too, otherwise the whole top-level tree is freed unrecorded and only
# subs with their own CvROOT survive.
sub test_do_file () {
  my $f = covered_file("TopDo", <<'PERL', <<'PROG', "11\n") or return;
package TopDo;
my $count = 0;
$count = $count + 1;
if ($count > 0) {
  $count = $count + 10;
}
sub val { $count }
1;
PERL
do "TopDo.pm";
print TopDo::val(), "\n";
PROG

  my $stmt = $f->statement;
  for my $line (2, 3, 4, 5) {
    my $l = $stmt->location($line);
    ok $l, "do-loaded top-level statement on line $line is collected";
    is $l && $l->[0]->covered, 1, "and has a count";
  }
  my $branch = $f->branch;
  ok $branch && $branch->location(4), "do-loaded top-level branch is collected";
}

# Under -subs_only Devel::Cover collects only subroutine coverage.  A
# file-scope anon sub of a required module is a subroutine body and must be
# reported like a main-program anon sub, so the require-tree pad walk has to
# run under -subs_only rather than being skipped with the top-level walk.
sub test_subs_only_anon () {
  my $f = covered_file("TopSubs",
    <<'PERL', <<'PROG', "10\n", {}, ",-subs_only,1") or return;
package TopSubs;
my $anon = sub { my $x = shift; $x * 2 };
sub named { $anon->(shift) }
1;
PERL
use TopSubs;
print TopSubs::named(5), "\n";
PROG

  my $subs = $f->subroutine;
  my $anon = $subs->location(2);
  ok $anon, "file-scope anon sub is collected under -subs_only";
  is $anon && $anon->[0]->name, "__ANON__", "and is the anon sub";
  ok $subs->location(3), "named sub is collected under -subs_only";
}

# Under -replace_ops 0 the collecting flag keeps whatever the last file set
# rather than consulting use_file, so without a filter at capture time every
# required file's optree is retained until report, only to be dropped by
# use_file there.  Run a program that requires a selected and an unselected
# module and report which files' trees are still held, read from
# get_require_trees before report.
sub retained_require_files (@opts) {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my %write  = (
    File::Spec->catfile($tmpdir, "Sel.pm") =>
      "package Sel;\nmy \$x = 1;\n1;\n",
    File::Spec->catfile($tmpdir, "Unsel.pm") =>
      "package Unsel;\nmy \$y = 1;\n1;\n",
    File::Spec->catfile($tmpdir, "prog.pl") => <<'PROG',
require Sel;
require Unsel;
my %seen;
for (Devel::Cover::get_require_trees()) {
  (my $base = $_->[2]) =~ s{.*[/\\]}{};
  $seen{$base}++;
}
print "REQTREES:", join(",", sort keys %seen), "\n";
PROG
  );
  for my $path (sort keys %write) {
    open my $fh, ">", $path or die "Cannot write $path: $!";
    print $fh $write{$path};
    close $fh or die "Cannot close $path: $!";
  }
  my $prog     = File::Spec->catfile($tmpdir, "prog.pl");
  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $opts = join "", @opts;
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$tmpdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0"
    . ",-select,Sel,-ignore,.$opts"
    . " $prog 2>&1";
  my $out = `$cmd`;
  my ($line) = $out =~ /^REQTREES:(.*)$/m;
  diag $out unless defined $line;
  +{ map { $_ => 1 } split /,/, $line // "" }
}

# With ops replaced (the default) use_file is consulted for every new file,
# so only the selected module's tree is retained.  With -replace_ops 0 the
# capture path must apply the same filter itself, or unselected trees pile up.
sub test_replace_ops_off_drops_unselected () {
  my $held = retained_require_files(",-replace_ops,0");
  ok $held->{"Sel.pm"}, "selected module tree is retained under -replace_ops 0";
  ok !$held->{"Unsel.pm"},
    "unselected module tree is not retained under -replace_ops 0";
}

sub main () {
  test_full_execution;
  test_partial_execution;
  test_anon_sub;
  test_require_unselected_last;
  test_glob_anon_single_record;
  test_reload_single_record;
  test_top_level_return;
  test_trailing_line_directive;
  test_enclosing_sub;
  test_do_file;
  test_subs_only_anon;
  test_replace_ops_off_drops_unselected;
  done_testing;
}

main;

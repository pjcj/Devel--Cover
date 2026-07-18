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
sub covered_file ($name, $module, $program, $expect, $extra = {}) {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));

  my %write = (
    File::Spec->catfile($tmpdir, "$name.pm") => $module,
    File::Spec->catfile($tmpdir, "prog.pl")  => $program,
    map { File::Spec->catfile($tmpdir, split m{/}) => $extra->{$_} }
      keys %$extra,
  );
  for my $path (sort keys %write) {
    make_path((File::Spec->splitpath($path))[1]);
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
    . ",-select,$name,-ignore,."
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

sub main () {
  test_full_execution;
  test_partial_execution;
  test_anon_sub;
  test_require_unselected_last;
  test_glob_anon_single_record;
  test_reload_single_record;
  done_testing;
}

main;

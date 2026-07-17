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
sub covered_file ($name, $module, $program, $expect) {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));

  my %write = (
    File::Spec->catfile($tmpdir, "$name.pm") => $module,
    File::Spec->catfile($tmpdir, "prog.pl")  => $program,
  );
  for my $path (sort keys %write) {
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
  my $f = covered_file("TopAnon", <<'PERL', <<'PROG', "3\n") or return;
package TopAnon;

my $add = sub {
  my ($x, $y) = @_;
  $x + $y
};

my $unused = sub {
  my ($x) = @_;
  $x * 2
};

sub call_add { $add->(1, 2) }

1;
PERL
use TopAnon;
print TopAnon::call_add(), "\n";
PROG

  my $stmt = $f->statement;
  ok $stmt->location(13), "named sub calling the anon sub is covered";
  # The assignment statement is attributed to the closing line of the
  # anon sub because its body resets the parser's statement-start line
  ok $stmt->location(6), "anon sub assignment statement is collected";

  my $l = $stmt->location(4);
  ok $l, "file-scope anon sub body is collected";
  is $l && $l->[0]->covered, 1, "and has a count";

  my $u = $stmt->location(9);
  ok $u, "uncalled anon sub body is collected";
  is $u && $u->[0]->covered, 0, "and is reported as uncovered";
}

sub main () {
  test_full_execution;
  test_partial_execution;
  test_anon_sub;
  done_testing;
}

main;

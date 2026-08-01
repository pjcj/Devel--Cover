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

# A sub redefined at runtime frees the original CV the moment its glob is
# overwritten, since nothing else references it.  The original ran and its
# counts were recorded, but by report time neither the symbol table nor any
# pad reaches it, so its statements and the subroutine itself vanish from
# the report.  This is the "Redefined subroutines" limitation documented in
# Cover.pod since GH-88.  See GH-606.

# Write a module and a program using it, run the program under coverage and
# return the cover object for the module's file.
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

# A named sub that runs and is then replaced in its glob with nothing keeping
# a reference to it.  The original body must still be reported as covered.
sub test_redefined_sub () {
  my $f = covered_file("Redefined", <<'PERL', <<'PROG', "11 20\n") or return;
package Redefined;

sub original {
  my $n = shift;
  $n * 2;
}

my $first = original(10);

*original = sub { shift() + 1 };

sub value { $first }

1;
PERL
use Redefined;
print Redefined::original(10), " ", Redefined::value(), "\n";
PROG

  my $stmt = $f->statement;
  for my $line (4, 5) {
    my $l = $stmt->location($line);
    ok $l, "redefined sub body statement on line $line is collected";
    is $l && $l->[0]->covered, 1, "and has a count";
  }

  my $sub = $f->subroutine->location(4);
  ok $sub, "the redefined original sub is collected";
  is $sub && $sub->[0]->name,    "original", "and keeps its name";
  is $sub && $sub->[0]->covered, 1,          "and is reported as covered";
}

# A named sub redefined before it ever runs.  The original never executed, so
# entry capture cannot see it and its optree is gone - it stays absent from
# the report.  The file must still report cleanly.
sub test_redefined_before_run () {
  my $f = covered_file("Unrun", <<'PERL', <<'PROG', "11\n") or return;
package Unrun;

sub original {
  my $n = shift;
  $n * 2;
}

*original = sub { shift() + 1 };

1;
PERL
use Unrun;
print Unrun::original(10), "\n";
PROG

  my $sub = $f->subroutine->location(4);
  is $sub, undef, "a never-run redefined sub stays absent from the report";
}

sub main () {
  test_redefined_sub;
  test_redefined_before_run;
  done_testing;
}

main;

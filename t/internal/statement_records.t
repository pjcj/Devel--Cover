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
use Test::More import => [qw( diag done_testing is is_deeply ok )];

use Devel::Cover::DB            ();
use Devel::Cover::DB::Structure ();

my $Rec = <<'PERL';
package Rec;

sub pick {
  my $n = shift;
  if ($n > 1) {
    return "big";
  }
  "small"
}

1;
PERL

my $Plain = <<'PERL';
package Plain;

our $Value = 1;

1;
PERL

my $Prog = <<'PERL';
use Rec;
use Plain;
print Rec::pick(2), "\n";
PERL

sub write_files ($tmpdir) {
  my %write = ("Rec.pm" => $Rec, "Plain.pm" => $Plain, "prog.pl" => $Prog);
  for my $name (sort keys %write) {
    my $path = File::Spec->catfile($tmpdir, $name);
    open my $fh, ">", $path or die "Cannot write $path: $!";
    print $fh $write{$name};
    close $fh or die "Cannot close $path: $!";
  }
}

sub run_program ($tmpdir, $cover_db, $criteria, $merge) {
  my $prog = File::Spec->catfile($tmpdir, "prog.pl");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$tmpdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,$merge"
    . ",-coverage,$criteria,-select,Rec,-select,Plain,-ignore,."
    . " $prog 2>&1";
  my $out = `$cmd`;
  is $?,   0,       "$criteria: covered run exits 0" or diag $out;
  is $out, "big\n", "$criteria: module code ran";
  return
}

# Run the program under $criteria coverage into a fresh database.
sub run_coverage ($criteria) {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  write_files($tmpdir);

  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  run_program($tmpdir, $cover_db, $criteria, 0);

  my $db   = Devel::Cover::DB->new(db => $cover_db)->merge_runs;
  my @runs = values $db->{runs}->%*;
  is @runs, 1, "$criteria: the database holds one run";
  my $run = $runs[0];

  my ($rec)   = grep m|/Rec\.pm$|,   keys $run->{digests}->%*;
  my ($plain) = grep m|/Plain\.pm$|, keys $run->{digests}->%*;
  ok $rec,   "$criteria: Rec.pm is in the run";
  ok $plain, "$criteria: Plain.pm is in the run";

  my $st = Devel::Cover::DB::Structure->new(base => $cover_db)->read_all;
  ($run, $rec, $plain, $st, $db)
}

sub test_subroutine_only () {
  my ($run, $rec, $plain, $st) = run_coverage("subroutine");
  is_deeply $run->{collected}, ["subroutine"],
    "subroutine: only subroutine coverage is collected";
  ok exists $run->{count}{$rec}{subroutine},
    "subroutine: Rec.pm has subroutine counts";
  ok !exists $run->{count}{$rec}{statement},
    "subroutine: Rec.pm has no statement counts";
  ok !$st->get_statement($run->{digests}{$rec}),
    "subroutine: the structure holds no statements for Rec.pm";
  ok exists $run->{count}{$plain},
    "subroutine: Plain.pm, which holds no subs, is in the counts";
}

sub test_statement_and_subroutine () {
  my ($run, $rec, undef, $st) = run_coverage("statement,subroutine");
  ok exists $run->{count}{$rec}{statement}
    && exists $run->{count}{$rec}{subroutine},
    "statement,subroutine: Rec.pm has statement and subroutine counts";
  my $statements = $st->get_statement($run->{digests}{$rec});
  ok $statements && @$statements,
    "statement,subroutine: the structure holds statements for Rec.pm";
}

sub test_subroutine_and_time () {
  my ($run, $rec) = run_coverage("subroutine,time");
  ok exists $run->{count}{$rec}{statement} && exists $run->{count}{$rec}{time},
    "subroutine,time: Rec.pm has statement and time counts";
}

# Map each line of $file to the statement counts on it.
sub statement_counts ($db, $file) {
  my $crit   = $db->cover->file($file)->statement;
  my $counts = $crit
    && { map { $_ => [map $_->covered, $crit->location($_)->@*] } keys %$crit };
  $counts
}

sub test_merged_statement_run () {
  my (undef, $want_rec, $want_plain, undef, $want_db)
    = run_coverage("statement");
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  write_files($tmpdir);
  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  run_program($tmpdir, $cover_db, "subroutine", 0);
  run_program($tmpdir, $cover_db, "statement",  1);
  my $db          = Devel::Cover::DB->new(db => $cover_db)->merge_runs;
  my ($got_rec)   = grep m|/Rec\.pm$|,   $db->cover->items;
  my ($got_plain) = grep m|/Plain\.pm$|, $db->cover->items;

  # A structure without statements must not stop a later run from adding them
  is_deeply statement_counts($db, $got_rec),
    statement_counts($want_db, $want_rec),
    "merge: Rec.pm statement coverage matches a statement-only run";
  is_deeply statement_counts($db, $got_plain),
    statement_counts($want_db, $want_plain),
    "merge: Plain.pm statement coverage matches a statement-only run";
}

sub main () {
  test_subroutine_only;
  test_statement_and_subroutine;
  test_subroutine_and_time;
  test_merged_statement_run;
  done_testing;
}

main;

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

# Run the program under $criteria coverage into a fresh database.
sub run_coverage ($criteria) {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  write_files($tmpdir);

  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  my $prog     = File::Spec->catfile($tmpdir, "prog.pl");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$tmpdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0"
    . ",-coverage,$criteria,-select,Rec,-select,Plain,-ignore,."
    . " $prog 2>&1";
  my $out = `$cmd`;
  is $?,   0,       "$criteria: covered run exits 0" or diag $out;
  is $out, "big\n", "$criteria: module code ran";

  my $db   = Devel::Cover::DB->new(db => $cover_db)->merge_runs;
  my @runs = values $db->{runs}->%*;
  is @runs, 1, "$criteria: the database holds one run";
  my $run = $runs[0];

  my ($rec)   = grep m|/Rec\.pm$|,   keys $run->{digests}->%*;
  my ($plain) = grep m|/Plain\.pm$|, keys $run->{digests}->%*;
  ok $rec,   "$criteria: Rec.pm is in the run";
  ok $plain, "$criteria: Plain.pm is in the run";

  my $st = Devel::Cover::DB::Structure->new(base => $cover_db)->read_all;
  ($run, $rec, $plain, $st)
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

sub main () {
  test_subroutine_only;
  test_statement_and_subroutine;
  test_subroutine_and_time;
  done_testing;
}

main;

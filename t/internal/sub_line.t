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
use Test::More import => [qw( diag done_testing is ok skip )];

use Devel::Cover::DB ();

# Subroutine and pod coverage belong on the line where the sub's body opens,
# which is the sub line in the usual style, not on the first statement.

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
    . ",-coverage,statement,subroutine,pod,-select,$name,-ignore,."
    . " $prog 2>&1";
  my $out = `$cmd`;
  is $?,   0,       "$name: covered run exits 0" or diag $out;
  is $out, $expect, "$name: module code ran";

  my $db     = Devel::Cover::DB->new(db => $cover_db)->merge_runs;
  my ($file) = grep m|\Q$name\E\.pm$|, $db->cover->items;
  ok $file, "$name.pm is in the coverage database" or return;
  $db->cover->file($file)
}

sub is_sub_at ($f, $line, $name, $covered) {
  my $loc = $f->subroutine->location($line);
  ok $loc, "$name is recorded on line $line" or return;
  is $loc->[0]->name,    $name,    "line $line holds $name";
  is $loc->[0]->covered, $covered, "$name covered count is $covered";
}

sub test_sub_lines () {
  my $f = covered_file("Subline", <<'PERL', <<'PROG', "20 1 42 3\n") or return;
package Subline;

=head2 body_below

=cut

sub body_below {
  my $n = shift;
  $n * 2;
}

sub brace_below
{
  1;
}

sub one_line { 42 }

sub empty {
}

my $anon = sub {
  3
};

sub call_anon { $anon->() }

1;
PERL
use Subline;
print join(" ", Subline::body_below(10), Subline::brace_below(),
  Subline::one_line(), Subline::call_anon()), "\n";
PROG

  is_sub_at $f, 7,  "body_below",  1;
  is_sub_at $f, 13, "brace_below", 1;
  is_sub_at $f, 17, "one_line",    1;
  is_sub_at $f, 19, "empty",       0;
  is_sub_at $f, 22, "__ANON__",    1;
  is_sub_at $f, 26, "call_anon",   1;

  is $f->subroutine->location(8), undef,
    "nothing is recorded on the first statement of body_below";

  SKIP: {
    skip "Pod::Coverage not available", 4
      unless eval { require Pod::Coverage; 1 };
    my $pod = $f->pod->location(7);
    ok $pod, "pod coverage for body_below is on the sub line" or return;
    is $pod->[0]->covered, 1, "and body_below is documented";
    $pod = $f->pod->location(13);
    ok $pod, "pod coverage for brace_below is on the brace line" or return;
    is $pod->[0]->covered, 0, "and brace_below is not documented";
  }
}

sub main () {
  test_sub_lines;
  done_testing;
}

main;

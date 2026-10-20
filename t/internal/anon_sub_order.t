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

# Two anonymous subs on one line must be recorded in source order whatever
# the hash seed, and each must have its own subroutine entry.

# Hash seeds 1 and 3 usually order the two subs differently on perl 5.44.
my ($Seed_a, $Seed_b) = (1, 3);

my $Anon = join "", map "$_\n", "package Anon;",
  'our %h = (a => sub { my $x = shift; $x ? "a1" : "a0" },'
  . ' b => sub { my $y = shift; $y ? "b1" : "b0" });', "1;";

my $Prog = <<'PROG';
use Anon;
print $Anon::h{$ARGV[0]}->(1), "\n";
PROG

sub write_files ($dir, $name, $module, $program) {
  my %write = (
    File::Spec->catfile($dir, "$name.pm") => $module,
    File::Spec->catfile($dir, "prog.pl")  => $program,
  );
  for my $path (sort keys %write) {
    open my $fh, ">", $path or die "Cannot write $path: $!";
    print $fh $write{$path};
    close $fh or die "Cannot close $path: $!";
  }
}

# Run the program under coverage with the given hash seed, adding to the
# database at $cover_db, and return the cover object for the file of the module.
sub covered_file ($name, $module, $program, $arg, $seed, $cover_db) {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  write_files($tmpdir, $name, $module, $program);

  my $prog = File::Spec->catfile($tmpdir, "prog.pl");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  local $ENV{PERL_HASH_SEED}    = $seed;
  local $ENV{PERL_PERTURB_KEYS} = 0;
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$tmpdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,1"
    . ",-coverage,statement,branch,subroutine,-select,$name,-ignore,."
    . " $prog $arg 2>&1";
  my $out = `$cmd`;
  is $?,   0, "$name $arg seed $seed: covered run exits 0" or diag $out;
  is $out, "${arg}1\n", "$name $arg seed $seed: module code ran";

  my $db     = Devel::Cover::DB->new(db => $cover_db)->merge_runs;
  my ($file) = grep m|\Q$name\E\.pm$|, $db->cover->items;
  ok $file, "$name.pm is in the coverage database" or return;
  $db->cover->file($file)
}

sub new_db () {
  File::Spec->catdir(realpath(tempdir(CLEANUP => 1)), "cover_db")
}

sub run_anon ($arg, $seed, $cover_db = new_db) {
  covered_file("Anon", $Anon, $Prog, $arg, $seed, $cover_db)
}

sub is_branch ($f, $line, $i, $text, $true, $desc) {
  my $b = $f->branch->location($line);
  ok $b, "$desc: branches are recorded on line $line" or return;
  is $b->[$i]->text,        $text, "$desc: branch $i is $text";
  is $b->[$i]->values->[0], $true, "$desc: branch $i true count is $true";
}

sub test_order () {
  for my $seed ($Seed_a, $Seed_b) {
    my $f = run_anon("a", $seed) or next;
    is_branch $f, 2, 0, '$x ? :', 1, "seed $seed";
    is_branch $f, 2, 1, '$y ? :', 0, "seed $seed";
  }
}

sub test_merged () {
  my $db = new_db;
  run_anon("a", $Seed_a, $db)         or return;
  my $f = run_anon("b", $Seed_b, $db) or return;
  is_branch $f, 2, 0, '$x ? :', 1, "merged";
  is_branch $f, 2, 1, '$y ? :', 1, "merged";
}

sub is_anon_entries ($f, $counts, $desc) {
  my $loc = $f->subroutine->location(2);
  ok $loc, "$desc: subs are recorded on line 2" or return;
  my $n = @$counts;
  is @$loc, $n, "$desc: line 2 holds $n entries";
  for my $i (0 .. $#$counts) {
    my $sub = $loc->[$i] or next;
    is $sub->name,    "__ANON__",    "$desc: entry $i is anonymous";
    is $sub->covered, $counts->[$i], "$desc: entry $i count is $counts->[$i]";
  }
}

sub test_entries () {
  my $f = run_anon("a", $Seed_b) or return;
  is_anon_entries $f, [1, 0], "a only";
}

sub test_both () {
  my $db = new_db;
  run_anon("a", $Seed_a, $db)         or return;
  my $f = run_anon("b", $Seed_b, $db) or return;
  is_anon_entries $f, [1, 1], "a and b";
}

sub test_single () {
  my $f = covered_file("Single", <<'PERL', <<'PROG', "a", $Seed_a, new_db)
package Single;
our %h = (a => sub { my $x = shift; $x ? "a1" : "a0" });
1;
PERL
use Single;
print $Single::h{$ARGV[0]}->(1), "\n";
PROG
    or return;
  is_anon_entries $f, [1], "single";
}

sub test_empty () {
  for my $seed ($Seed_a, $Seed_b) {
    my $f = covered_file("Empty", <<'PERL', <<'PROG', "b", $seed, new_db)
package Empty;
our %h = (a => sub {}, b => sub { my $y = shift; $y ? "b1" : "b0" });
1;
PERL
use Empty;
print $Empty::h{$ARGV[0]}->(1), "\n";
PROG
      or next;
    is_anon_entries $f, [0, 1], "empty seed $seed";
    is_branch $f, 2, 0, '$y ? :', 1, "empty seed $seed";
  }
}

sub main () {
  test_order;
  test_merged;
  test_entries;
  test_both;
  test_single;
  test_empty;
  done_testing;
}

main;

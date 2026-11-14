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
use Test::More import => [qw( diag done_testing is is_deeply ok unlike )];

use Devel::Cover::DB ();

my $Module = <<'PERL';
package Early;

sub sorted {
  my @l = sort { $a <=> $b } @_;
  @l;
}

sub never {
  my $x = 1;
  $x;
}

sub sorted_one { my @l = sort { $a <=> $b } @_;
  @l;
}

sub never_one { my $x = 1;
  $x;
}

sub by_early { 5 }

sub lv :lvalue {
  $Early::X;
}

1;
PERL

my $Late = <<'PERL';
use Early;
print join(" ", Early::sorted(2, 1), Early::sorted_one(4, 3)), "\n";
Early::lv() = 2;
PERL

my $Early = <<'PERL';
Early::sorted(2, 1);
Early::sorted_one(4, 3);
Early::by_early();
Early::lv() = 3;
PERL

my $Output = { late => "1 2 3 4\n", early => "", early_runops => "" };

sub write_file ($dir, $name, $content) {
  my $path = File::Spec->catfile($dir, $name);
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
  $path
}

sub setup ($criteria) {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  write_file($tmpdir, "Early.pm", $Module);
  my $late  = write_file($tmpdir, "late.pl",  $Late);
  my $early = write_file($tmpdir, "early.pl", $Early);

  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  my $perl     = "$^X -Iblib/lib -Iblib/arch -I$tmpdir";
  my $cover    = "-MDevel::Cover=-db,$cover_db,-coverage,$criteria"
    . ",-select,Early,-ignore,.";

  {
    cover_db => $cover_db,
    # Devel::Cover loads before perl compiles Early
    late => "$perl $cover,-silent,1 $late 2>&1",
    # Perl loads -MEarly before -MDevel::Cover, so it compiles Early first
    early        => "$perl -MEarly $cover,-silent,1 $early 2>&1",
    early_runops => "$perl -MEarly $cover,-silent,1,-replace_ops,0 $early 2>&1",
    early_loud   => "$perl -MEarly $cover $early 2>&1",
  }
}

sub covered_file ($criteria, @order) {
  my $s = setup($criteria);
  delete local $ENV{DEVEL_COVER_SELF};
  for my $name (@order) {
    my $out = `$s->{$name}`;
    is $?,   0,                "@order: the $name run exits 0" or diag $out;
    is $out, $Output->{$name}, "@order: the $name run prints what it should";
  }

  my $db     = Devel::Cover::DB->new(db => $s->{cover_db})->merge_runs;
  my ($file) = grep m|Early\.pm$|, $db->cover->items;
  $file && $db->cover->file($file)
}

sub subs ($f) {
  my $sub = $f->subroutine;
  my @subs;
  for my $line (sort { $a <=> $b } $sub->items) {
    push @subs, map [$line, $_->name, $_->covered], $sub->location($line)->@*;
  }
  \@subs
}

sub statements ($f, $line) {
  [map $_->covered, ($f->statement->location($line) // [])->@*]
}

my $Late_subs = [
  [3,  "sorted",     1],
  [8,  "never",      0],
  [13, "sorted_one", 1],
  [17, "never_one",  0],
  [21, "by_early",   0],
  [23, "lv",         1],
];

sub test_merged (@order) {
  my $f = covered_file("statement,subroutine", @order);
  ok $f, "@order: Early.pm is in the coverage database" or return;
  is_deeply subs($f), $Late_subs,
    "@order: each sub is recorded once, with the count of the late run";
  is_deeply statements($f, $_), [1], "@order: the statement on line $_ ran once"
    for 5, 14, 24;
  is_deeply statements($f, $_), [0],
    "@order: the statement on line $_ never ran"
    for 9, 10, 17, 18;
}

sub test_subroutine_only () {
  my $f = covered_file("subroutine", qw( late early ));
  ok $f, "subroutine only: Early.pm is in the coverage database" or return;
  is_deeply subs($f), $Late_subs,
    "subroutine only: the early run adds no sub and no count";
}

sub test_early_alone () {
  ok !covered_file("statement,subroutine", "early"),
    "early: a process records nothing for a module compiled before it loaded";

  my $s = setup("statement,subroutine");
  delete local $ENV{DEVEL_COVER_SELF};
  my $out = `$s->{early_loud}`;
  is $?, 0, "early: a run that is not silent exits 0" or diag $out;
  unlike $out, qr/Can't find digest/, "  and does not look for the module";
}

sub test_early_runops () {
  my $f = covered_file("statement,subroutine", "early_runops");
  ok $f, "early_runops: Early.pm is in the coverage database" or return;
  is_deeply subs($f), [
      [4,  "sorted",     1],
      [9,  "never",      0],
      [13, "sorted_one", 1],
      [17, "never_one",  0],
      [21, "by_early",   1],
      [24, "lv",         1],
    ],
    "early_runops: without op replacement the module is counted";
}

sub main () {
  test_merged qw( late early );
  test_merged qw( early late );
  test_subroutine_only;
  test_early_alone;
  test_early_runops;
  done_testing;
}

main;

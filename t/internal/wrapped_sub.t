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
use Test::More import => [qw( diag done_testing is ok $TODO )];

use Devel::Cover::DB ();

# Set within a TODO block for the cases the heuristic cannot yet recover
our $TODO;

# A named sub replaced in the symbol table by a wrapper survives only as a
# reference held inside the wrapper's closure pad, no longer reachable from any
# stash glob.  Devel::Cover discovers subs from stash glob slots and from direct
# CV pad values, but not from a pad slot that is a reference to a CV, so the
# original sub is never found and its statements, though instrumented and
# executed, are dropped from the report.  The file then reports full coverage
# while the original body is invisible.  This is the pattern behind Moose
# "around" and every other method modifier.  See GH-308.

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

# A named sub kept in a lexical, then replaced in its glob by a wrapper closing
# over that lexical.  The original runs when the wrapper calls it, so its body
# statements and the subroutine itself must be covered rather than omitted.
# This is the reduced form of a method modifier.
sub test_glob_wrapped_sub () {
  my $f = covered_file("Wrapped", <<'PERL', <<'PROG', "21\n") or return;
package Wrapped;

sub original {
  my $n = shift;
  $n * 2;
}

my $orig = \&original;
*original = sub { $orig->(shift) + 1 };

1;
PERL
use Wrapped;
print Wrapped::original(10), "\n";
PROG

  my $stmt = $f->statement;
  for my $line (4, 5) {
    my $l = $stmt->location($line);
    ok $l, "wrapped sub body statement on line $line is collected";
    is $l && $l->[0]->covered, 1, "and has a count";
  }

  my $subs = $f->subroutine;
  my $sub  = $subs->location(4);
  ok $sub, "the wrapped original sub is collected";
  is $sub && $sub->[0]->name,    "original", "and keeps its name";
  is $sub && $sub->[0]->covered, 1,          "and is reported as covered";
}

# A wrapper that reaches the original through a plain hash it closes over,
# rather than a direct lexical.  This is how Class::MOP (and so Moose) holds
# the original method, so the pad walk must descend through the hash to find
# it.
sub test_hash_wrapped_sub () {
  my $f = covered_file("WrappedHash", <<'PERL', <<'PROG', "21\n") or return;
package WrappedHash;

sub original {
  my $n = shift;
  $n * 2;
}

my %tbl = (orig => \&original);
*original = sub { $tbl{orig}->(shift) + 1 };

1;
PERL
use WrappedHash;
print WrappedHash::original(10), "\n";
PROG

  my $stmt = $f->statement;
  for my $line (4, 5) {
    my $l = $stmt->location($line);
    ok $l, "hash-held wrapped sub body statement on line $line is collected";
    is $l && $l->[0]->covered, 1, "and has a count";
  }
  my $sub = $f->subroutine->location(4);
  ok $sub, "the hash-held wrapped sub is collected";
  is $sub && $sub->[0]->covered, 1, "and is reported as covered";
}

# A wrapper that reaches the original through a plain array it closes over,
# the list-of-modifiers form.  The pad walk must descend through the array.
sub test_array_wrapped_sub () {
  my $f = covered_file("WrappedArray", <<'PERL', <<'PROG', "21\n") or return;
package WrappedArray;

sub original {
  my $n = shift;
  $n * 2;
}

my @mods = (\&original);
*original = sub { $mods[0]->(shift) + 1 };

1;
PERL
use WrappedArray;
print WrappedArray::original(10), "\n";
PROG

  my $stmt = $f->statement;
  for my $line (4, 5) {
    my $l = $stmt->location($line);
    ok $l, "array-held wrapped sub body statement on line $line is collected";
    is $l && $l->[0]->covered, 1, "and has a count";
  }
  my $sub = $f->subroutine->location(4);
  ok $sub, "the array-held wrapped sub is collected";
  is $sub && $sub->[0]->covered, 1, "and is reported as covered";
}

# The motivating case: a Moose "around" modifier.  Moose installs a
# Class::MOP wrapper into the method glob and keeps the original method only
# inside the wrapper's closure hash, so the original body vanishes from
# coverage unless the pad walk descends into that hash.  Moose is loaded
# through a variable so a bareword require does not make perlcritic treat
# this test as a Moose class.
sub test_moose_around_original () {
  my $moose = "Moose.pm";
  return unless eval { require $moose; 1 };
  my $f = covered_file("MooseAnimal", <<'PERL', <<'PROG', "loud generic\n");
package MooseAnimal;
use Moose;

sub speak {
  my $self = shift;
  "generic";
}

around speak => sub {
  my ($orig, $self) = @_;
  "loud " . $self->$orig;
};

__PACKAGE__->meta->make_immutable;
1;
PERL
use MooseAnimal;
my $a = MooseAnimal->new;
print $a->speak, "\n";
PROG
  return unless $f;

  my $sub = $f->subroutine->location(5);
  ok $sub, "the original around-wrapped method is collected";
  is $sub && $sub->[0]->name,    "speak", "and keeps its name";
  is $sub && $sub->[0]->covered, 1,       "and is reported as covered";

  my $l = $f->statement->location(6);
  ok $l, "the original method body statement is collected";
  is $l && $l->[0]->covered, 1, "and has a count";
}

# The cases below are the documented limits of the reference-following
# heuristic (docs/technical/wrapped-sub-coverage.md).  Each original runs but
# is not recovered, so the assertions are wrapped in a TODO block - they are
# the red anchor for the entry-capture follow-up, and will flip to passing
# (unexpectedly) once that lands, which is the signal to drop the TODO.

# The original sits two containers deep, past the single level the heuristic
# descends.
sub test_deep_container_todo () {
  my $f = covered_file("WrappedDeep", <<'PERL', <<'PROG', "21\n") or return;
package WrappedDeep;

sub original {
  my $n = shift;
  $n * 2;
}

my $reg = { inner => { orig => \&original } };
*original = sub { $reg->{inner}{orig}->(shift) + 1 };

1;
PERL
use WrappedDeep;
print WrappedDeep::original(10), "\n";
PROG

  local $TODO = "original nested past one container is not yet recovered";
  my $sub = $f->subroutine->location(4);
  ok $sub, "deeply-held wrapped sub is collected";
  is $sub && $sub->[0]->covered, 1, "and is reported as covered";
}

# The original is kept in a blessed object the wrapper closes over, which the
# heuristic does not descend.
sub test_blessed_holder_todo () {
  my $f = covered_file("WrappedBlessed", <<'PERL', <<'PROG', "21\n") or return;
package WrappedBlessed;

sub original {
  my $n = shift;
  $n * 2;
}

my $holder = bless { orig => \&original }, "WrappedBlessed::Holder";
*original = sub { $holder->{orig}->(shift) + 1 };

1;
PERL
use WrappedBlessed;
print WrappedBlessed::original(10), "\n";
PROG

  local $TODO = "original held in a blessed object is not yet recovered";
  my $sub = $f->subroutine->location(4);
  ok $sub, "blessed-held wrapped sub is collected";
  is $sub && $sub->[0]->covered, 1, "and is reported as covered";
}

# The original is kept in a package variable and looked up at call time, so it
# is in no pad the walk reaches.
sub test_global_registry_todo () {
  my $f = covered_file("WrappedReg", <<'PERL', <<'PROG', "21\n") or return;
package WrappedReg;

sub original {
  my $n = shift;
  $n * 2;
}

our %REG = (orig => \&original);
*original = sub { $REG{orig}->(shift) + 1 };

1;
PERL
use WrappedReg;
print WrappedReg::original(10), "\n";
PROG

  local $TODO = "original kept in a package variable is not yet recovered";
  my $sub = $f->subroutine->location(4);
  ok $sub, "registry-held wrapped sub is collected";
  is $sub && $sub->[0]->covered, 1, "and is reported as covered";
}

sub main () {
  test_glob_wrapped_sub;
  test_hash_wrapped_sub;
  test_array_wrapped_sub;
  test_moose_around_original;
  test_deep_container_todo;
  test_blessed_holder_todo;
  test_global_registry_todo;
  done_testing;
}

main;

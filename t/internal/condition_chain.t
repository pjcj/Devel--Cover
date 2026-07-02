#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# A short-circuit that resolves a chain of same-type logops takes one
# jump: Perl points the op_next of chained logops past their parents,
# so the outer logops never execute.  The recorder climbs the chain to
# mark each skipped logop as short-circuited.  The climb must survive
# nulled right operands (element accesses) and chains of more than two
# logops.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Cwd        qw( abs_path );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is is_deeply ok subtest )];

use Devel::Cover::DB ();

my $Tmpdir = tempdir(CLEANUP => 1);

sub write_script ($name, $content) {
  my $path = File::Spec->catfile($Tmpdir, $name);
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
  $path
}

sub run_under_cover ($script, $label) {
  my $cover_db   = File::Spec->catdir($Tmpdir, "cover_db_$label");
  my $abs_tmpdir = abs_path($Tmpdir);
  my @cmd        = (
    $^X,
    "-Iblib/lib",
    "-Iblib/arch",
    "-MDevel::Cover=-db,$cover_db,-silent,1,"
      . "-coverage,condition,+select,$abs_tmpdir",
    $script,
  );
  system(@cmd) == 0 or die "Failed to run script under Devel::Cover: @cmd";

  my $db = Devel::Cover::DB->new(db => $cover_db);
  $db->merge_runs;
  ($db->cover, abs_path($script))
}

# Condition hit counts for a line, outermost record first.  Records come
# back in outermost-first order but the text is the stable identity, so
# sort by text length: an outer record's text contains its inner ones.
sub values_for ($cover, $file, $line) {
  my $cond = $cover->file($file)->criterion("condition") or return [];
  my @recs
    = sort { length $b->{text} <=> length $a->{text} }
    map +{ text => $_->text, values => [$_->values] },
    ($cond->location($line) // [])->@*;
  [map $_->{values}, @recs]
}

# decide(1, 0, 0, 0) short-circuits at the innermost logop; the jump
# skips both outer logops, which must each be marked short-circuited
# (slot 0, the "l" column for or).
sub test_lexical_chain_cascade () {
  my $script = write_script("lex_chain.pl", <<'PERL');
sub decide { my ($a, $b, $c, $d) = @_; my $r = $a || $b || $c || $d; $r }
decide(1, 0, 0, 0);
PERL

  my ($cover, $path) = run_under_cover($script, "lex_chain");
  is_deeply values_for($cover, $path, 1), [[1, 0, 0], [1, 0, 0], [1, 0, 0]],
    "every logop in the chain is marked short-circuited";
}

# The right operands here are hash elements, whose optree roots are
# nulled ops; the climb must step through them to reach the outer
# logop.
sub test_element_chain_cascade () {
  my $script = write_script("element_chain.pl", <<'PERL');
sub decide { my %h = @_; my $r = $h{a} || $h{b} || $h{c}; $r }
decide(a => 1, b => 0, c => 0);
PERL

  my ($cover, $path) = run_under_cover($script, "element_chain");
  is_deeply values_for($cover, $path, 1), [[1, 0, 0], [1, 0, 0]],
    "both logops marked short-circuited through nulled operands";
}

# A short-circuit at the outermost logop only must not over-mark the
# inner one, which evaluated fully.
sub test_root_short_circuit_no_overmark () {
  my $script = write_script("root_sc.pl", <<'PERL');
sub decide { my %h = @_; my $r = $h{a} || $h{b} || $h{c}; $r }
decide(a => 0, b => 1, c => 0);
PERL

  my ($cover, $path) = run_under_cover($script, "root_sc");
  is_deeply values_for($cover, $path, 1), [[1, 0, 0], [0, 1, 0]],
    "outer marked short-circuited once, inner marked fully evaluated";
}

sub main () {
  subtest "lexical chain cascade" => \&test_lexical_chain_cascade;
  subtest "element chain cascade" => \&test_element_chain_cascade;
  subtest "root short circuit no overmark" =>
    \&test_root_short_circuit_no_overmark;

  done_testing;
}

main;

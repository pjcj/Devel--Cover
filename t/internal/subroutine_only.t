#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use lib "t/lib";

use Devel::Cover::Test::Internal qw( write_script run_under_cover );

use Test::More import => [qw( done_testing is ok )];

my $Source = <<'PERL';
sub called   { my $x = 42; $x }
sub uncalled { my $y = 43; $y }
my $anon = sub { my $z = 44; $z };
called() for 1 .. 3;
$anon->();
PERL

sub sub_counts ($file) {
  my %count;
  my $subs = $file->subroutine;
  for my $line ($subs->items) {
    $count{ $_->name } = $_->covered for $subs->location($line)->@*;
  }
  \%count
}

sub check_counts ($label, $counts) {
  is $counts->{called},   3, "$label: the called sub counts its calls";
  is $counts->{uncalled}, 0, "$label: the uncalled sub is uncovered";
  is $counts->{__ANON__}, 1, "$label: the anonymous sub counts its call";
}

sub test_subroutine_only ($script, $mode, @options) {
  my $label = "subroutine only, $mode";
  my ($db, $path) = run_under_cover(
    $script, "subroutine_only_$mode",
    criteria => ["subroutine"],
    options  => \@options,
  );
  my $file = $db->cover->file($path);
  ok $file, "$label: the program is in the database" or return;
  check_counts($label, sub_counts($file));
}

sub test_with_statement ($script, $mode, @options) {
  my $label = "subroutine and statement, $mode";
  my ($db, $path) = run_under_cover(
    $script, "subroutine_statement_$mode",
    criteria => ["subroutine", "statement"],
    options  => \@options,
  );
  my $file = $db->cover->file($path);
  ok $file, "$label: the program is in the database" or return;
  check_counts($label, sub_counts($file));
}

sub main () {
  my $script = write_script("subroutine_only.pl", $Source);
  my %modes  = (replaced => [], runops => ["-replace_ops,0"]);
  for my $mode (sort keys %modes) {
    test_subroutine_only($script, $mode, $modes{$mode}->@*);
    test_with_statement($script, $mode, $modes{$mode}->@*);
  }
  done_testing;
}

main;

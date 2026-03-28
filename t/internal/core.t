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

use Test::More import => [ qw( done_testing is ) ];

use Cwd        qw( abs_path );
use File::Spec ();

use Devel::Cover::Core qw( remove_contained_paths );

sub test_contained_paths_removed () {
  my $cwd = abs_path "t/internal/inc_filter/cwd";

  my @inc = remove_contained_paths(
    $cwd,
    map {
      my $p = "t/internal/inc_filter/$_";
      map { $_, lcfirst } abs_path($p), File::Spec->rel2abs($p)
    } qw( cwd cwd/lib cwd_lib )
  );

  is grep(/cwd_lib/, @inc), 4, "cwd_lib was left in the array four times";
  is @inc,                  4, "no other paths were left in the array";
}

sub main () {
  test_contained_paths_removed;
  done_testing;
}

main;

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use lib qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is )];

my $Pm    = "Autoloader_stale.pm";
my $Al    = "auto/Autoloader_stale/stale.al";
my $Stale = "blib/lib/$Pm (autosplit into blib/lib/$Al)";

sub parent ($file) { Devel::Cover::autosplit_parent($file) }

sub test_no_suffix () {
  is parent("tests/$Pm"), "tests/$Pm", "name without suffix is unchanged";
}

sub test_existing_path () {
  is parent("tests/$Pm (autosplit into tests/$Al)"), "tests/$Pm",
    "suffix stripped when the path still exists";
}

sub test_stale_blib_lib () {
  local $INC{$Pm} = "tests/$Pm";
  is parent($Stale), "tests/$Pm", "stale blib/lib path recovered from %INC";
}

sub test_stale_blib_arch () {
  local $INC{$Pm} = "tests/$Pm";
  is parent("blib/arch/$Pm (autosplit into blib/arch/$Al)"), "tests/$Pm",
    "stale blib/arch path recovered from %INC";
}

sub test_mixed_prefixes () {
  local $INC{$Pm} = "tests/$Pm";
  is parent("blib/arch/$Pm (autosplit into blib/lib/$Al)"), "tests/$Pm",
    ".pm and .al under different blib prefixes";
}

sub test_inc_miss () {
  local %INC = %INC;
  delete $INC{$Pm};
  is parent($Stale), "blib/lib/$Pm", "no %INC entry degrades to stripped name";
}

sub test_inc_ref () {
  local $INC{$Pm} = sub { };
  is parent($Stale), "blib/lib/$Pm", "%INC hook ref degrades to stripped name";
}

sub test_inc_odd_value () {
  local $INC{$Pm} = "/somewhere/else.pm";
  is parent($Stale), "blib/lib/$Pm",
    "%INC value not ending in the key degrades to stripped name";
}

sub test_al_missing () {
  local $INC{$Pm} = "t/internal/$Pm";
  is parent($Stale), "blib/lib/$Pm",
    "no .al under the %INC root degrades to stripped name";
}

sub test_non_blib_stale () {
  is parent("../../lib/POSIX.pm (autosplit into ../../lib/auto/POSIX/f.al)"),
    "../../lib/POSIX.pm", "non-blib stale path is only stripped";
}

sub main () {
  # a compile-time use would run CHECK blocks needing the unbootstrapped XS
  require Devel::Cover;

  test_no_suffix;
  test_existing_path;
  test_stale_blib_lib;
  test_stale_blib_arch;
  test_mixed_prefixes;
  test_inc_miss;
  test_inc_ref;
  test_inc_odd_value;
  test_al_missing;
  test_non_blib_stale;
  done_testing;
}

main;

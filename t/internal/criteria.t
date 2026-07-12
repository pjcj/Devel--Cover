#!/usr/bin/perl

# Copyright 2010-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Test::More;

require Devel::Cover;
Devel::Cover->import(qw( -silent 1 ));
plan tests => 5;

Devel::Cover::set_coverage("none");
is Devel::Cover::get_coverage(), "", "Set coverage to none empties coverage";

Devel::Cover::set_coverage("all");
is Devel::Cover::get_coverage(),
  "branch condition mcdc pod statement subroutine time",
  "Set coverage to all fills coverage";

Devel::Cover::remove_coverage("mcdc");
is Devel::Cover::get_coverage(),
  "branch condition pod statement subroutine time",
  "Removing mcdc coverage works";

{
  my $warning;
  local $SIG{__WARN__} = sub { $warning = shift };
  Devel::Cover::add_coverage("does_not_exist");
  like $warning,
    qr/Devel::Cover: Unknown coverage criterion "does_not_exist" ignored./,
    "Adding nonexistent coverage warns";
}
is Devel::Cover::get_coverage(),
  "branch condition pod statement subroutine time",
  "Adding nonexistent coverage has no effect";

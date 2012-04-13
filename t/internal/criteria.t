use strict;
use warnings;

use Test::More;
use Test::Warn;

if ($] < 5.008000)
{
    plan skip_all => "Test requires perl 5.8.0 or greater";
}
if ($] == 5.015006)
{
    plan skip_all => "5.15.6 throws too many erroneous warnings";
}
else
{
    require Devel::Cover;
    Devel::Cover->import(qw( -silent 1 ));
    plan tests => 5;
}

Devel::Cover::set_coverage("none");
is Devel::Cover::get_coverage(),
   "",
   "Set coverage to none empties coverage";

Devel::Cover::set_coverage("all");
is Devel::Cover::get_coverage(),
   "branch condition path pod statement subroutine time",
   "Set coverage to all fills coverage";

Devel::Cover::remove_coverage("path");
is Devel::Cover::get_coverage(),
   "branch condition pod statement subroutine time",
   "Removing path coverage works";

warning_like { Devel::Cover::add_coverage("does_not_exist") }
   qr/Devel::Cover: Unknown coverage criterion "does_not_exist" ignored./,
   "Adding non-existent coverage warns";
is Devel::Cover::get_coverage(),
   "branch condition pod statement subroutine time",
   "Adding non-existent coverage has no effect";

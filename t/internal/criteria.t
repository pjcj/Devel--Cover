use strict;
use warnings;

use Test::More;

require Devel::Cover;
Devel::Cover->import(qw( -silent 1 ));
plan tests => 5;

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

{
    my $warning;
    local $SIG{__WARN__} = sub { $warning = shift };
    Devel::Cover::add_coverage("does_not_exist");
    like $warning,
         qr/Devel::Cover: Unknown coverage criterion "does_not_exist" ignored./,
         "Adding non-existent coverage warns";
}
is Devel::Cover::get_coverage(),
   "branch condition pod statement subroutine time",
   "Adding non-existent coverage has no effect";

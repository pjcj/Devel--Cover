use strict;
use warnings;

package test_inc_filter;

use Test::More;
use Cwd 'abs_path';
use File::Spec;
use Devel::Cover::Util 'remove_contained_paths';

plan tests => 2;

run();

sub run {
    my $cwd = abs_path "t/internal/inc_filter/cwd";

    my @inc_tests = qw( cwd cwd/lib cwd_lib );
    my @inc = map "t/internal/inc_filter/$_", @inc_tests;
    @inc = map { abs_path( $_ ), File::Spec->rel2abs( $_ ) } @inc;
    @inc = map { $_, lcfirst $_ } @inc;

    @inc = remove_contained_paths( $cwd, @inc );

    is ~~ ( grep { /cwd_lib/ } @inc ), 4,
       "cwd_lib was left in the array four times";
    is ~~ @inc, 4, "no other paths were left in the array";

    return;
}

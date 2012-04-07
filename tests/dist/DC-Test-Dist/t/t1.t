use strict;
use warnings;

use Test::More;

use DC::Test::Dist;

my $d = DC::Test::Dist->new;

$d->d1("a");
is $d->d1, "a", "d1 correctly set and retrieved";

done_testing

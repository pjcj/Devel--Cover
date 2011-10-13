use strict;
use warnings;

use Test::More;
use Devel::Cover;

use lib 'tests';

$SIG{__WARN__} = sub { die @_ };
require COP;
ok 1, "warnings in a file with file location comments don't cause a die";
done_testing;

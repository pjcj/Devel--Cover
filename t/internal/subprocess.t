use strict;
use warnings;

use Test::More;

plan tests => 2;

my $cmd = qq[$^X -e "print q(Hello, world.)"];
my $output = `$cmd 2>&1`;
is($output, "Hello, world.", "simple test with perl -e");

$cmd = qq[$^X -Mblib -MDevel::Cover=-silent,1 -e "print q(Hello, world.)"];
$output = `$cmd 2>&1`;
is($output, "Hello, world.", "test with perl -MDevel::Cover,-silent,1 -e");

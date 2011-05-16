use strict;
use warnings;

use Test::More;

if ($] < 5.008000)
{
    plan skip_all => "Test requires perl 5.8.0 or greater";
}
else
{
    plan tests => 2;
}

my $cmd = qq[$^X -e "print q(Hello, world.)"];
my $output = `$cmd 2>&1`;
is($output, "Hello, world.", "simple test with perl -e");

$cmd = qq[$^X -Mblib -MDevel::Cover=-silent,1 -e "print q(Hello, world.)"];
$output = `$cmd 2>&1`;
is($output, "Hello, world.", "test with perl -MDevel::Cover,-silent,1 -e");

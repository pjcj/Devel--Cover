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

my $cmd = "$^X -e 'print \"Hello World.\\n\"'";
my $output = `$cmd 2>&1`;
is($output, "Hello World.\n", 'simple test with perl -e');

$cmd = "$^X -Mblib -MDevel::Cover=-silent,1 -e 'print \"Hello World.\\n\"'";
$output = `$cmd 2>&1`;
is($output, "Hello World.\n", 'test with perl -MDevel::Cover,-silent,1 -e');

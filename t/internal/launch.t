use strict;
use warnings;

use Test::More;

opendir my $d, 'lib/Devel/Cover/Report';
my @reporters = grep { s/\.pm$// } readdir($d);
closedir $d;

plan tests => scalar @reporters;

my @reporters_with_launch = qw(
    Html Html_basic Html_minimal Html_subtle
);

# Check that the expected reporters support the launch feature
for my $reporter (@reporters) {
    my $class = 'Devel::Cover::Report::' . $reporter;
    eval "require $class";

    if (grep { $_ eq $reporter } @reporters_with_launch) {
        ok($class->can('launch'), "$reporter supports launch");
    }
    else {
        ok(! $class->can('launch'), "$reporter does not support launch");
    }
}

#!/usr/bin/perl

# Copyright 2014-2016, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

use strict;
use warnings;

use Devel::Cover::Test;

# print "QQQ\n";

if ($] == 5.008007) {
    eval "use Test::More skip_all => 'Crashes 5.8.7'";
    exit;
}

# print "RRR\n";

my $run_test = sub {
    my $test = shift;

    # print "UUU\n";

    $test->{test} = "eval_merge_0";
    $test->run_command($test->test_command);

    # print "VVV\n";

    $test->{test_parameters} .= " -merge 1";

    $test->{test} = "eval_merge_1";
    $test->run_command($test->test_command);
};

my $runs = 2;

my $test = Devel::Cover::Test->new(
    "eval_merge_sep",
    db_name     => "complex_eval_merge_sep",
    golden_test => "eval_merge_sep.t",
    run_test    => $run_test,
    changes     => [ 'if (/^Run: /) { $get_line->() for 1 .. 5; redo }' ],
    tests       => sub { $_[0] - $runs * 6 },  # number of lines deleted above
);

# print "SSS\n";

$test->run_test;

# print "TTT\n";

no warnings;
$test  # for create_gold

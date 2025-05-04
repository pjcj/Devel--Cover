#!/usr/bin/perl

# Copyright 2004-2025, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use strict;
use warnings;

use Devel::Cover::Test;

my $run_test = sub {
    my $test = shift;

    $test->run_command($test->test_command);

    $test->{test_parameters} .= " -merge 1";

    $test->{test_file_parameters} = "5";
    $test->run_command($test->test_command);

    $test->{test_file_parameters} = "7";
    $test->run_command($test->test_command);

    $test->{test_file_parameters} = "0";
    $test->run_command($test->test_command);
};

my $test = Devel::Cover::Test->new(
    "eval2",
    db_name     => "complex_eval_use",
    golden_test => "eval_use.t",
    run_test    => $run_test,
    changes     => [ 'if (/^Run: /) { $get_line->() for 1 .. 5; redo }' ],
    tests       => sub { $_[0] - 24 },  # number of lines deleted above
);

$test->run_test;
no warnings;
$test  # for create_gold

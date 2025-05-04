#!/usr/bin/perl

# Copyright 2002-2025, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use strict;
use warnings;

use File::Copy;

use Devel::Cover::Test;

my $t  = "md5";
my $ft = "./tests/$t";
my $fg = "./tests/trivial";

my $run_test = sub {
    my $test = shift;

    copy($fg, $ft) or die "Cannot copy $fg to $ft: $!";
    open T, ">>$ft" or die "Cannot open $ft: $!";
    print T "# blah blah\n";
    close T or die "Cannot close $ft: $!";
    $test->run_command($test->test_command);

    copy($fg, $ft) or die "Cannot copy $fg to $ft: $!";
    $test->{test_parameters} .= " -merge 1";
    $test->run_command($test->test_command);
};

my $test = Devel::Cover::Test->new(
    $t,
    db_name         => "complex_$t",
    run_test        => $run_test,
    end             => sub { unlink $ft },
    delay_after_run => 0.50,
);

$test->run_test;
no warnings;
$test  # for create_gold

#!/usr/bin/perl

# Copyright 2002-2011, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

use strict;
use warnings;

use File::Copy;

use Devel::Cover::Inc  0.78;
use Devel::Cover::Test 0.78;

my $base = $Devel::Cover::Inc::Base;

my $t  = "md5";
my $ft = "$base/tests/$t";
my $fg = "$base/tests/trivial";

if ($] == 5.008007)
{
    eval "use Test::More skip_all => 'Crashes 5.8.7'";
    exit;
}

my $run_test = sub
{
    my $test = shift;

    copy($fg, $ft) or die "Cannot copy $fg to $ft: $!";

    open T, ">>$ft" or die "Cannot open $ft: $!";
    print T "# blah blah\n";
    close T or die "Cannot close $ft: $!";

    $test->run_command($test->test_command);

    sleep 1;

    copy($fg, $ft) or die "Cannot copy $fg to $ft: $!";

    $test->{test_parameters} .= " -merge 1";
    $test->run_command($test->test_command);
};

my $test = Devel::Cover::Test->new
(
    $t,
    run_test => $run_test,
    end      => sub { unlink $ft },
);

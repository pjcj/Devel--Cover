#!/usr/bin/perl

# Copyright 2002-2004, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

use strict;
use warnings;

use File::Copy;

use Devel::Cover::Inc  0.49;
use Devel::Cover::Test 0.49;

my $base = $Devel::Cover::Inc::Base;

my $g  = "trivial";
my $t  = "trivial_md5";
my $fg = "$base/tests/$g";
my $ft = "$base/tests/$t";

sub run_test
{
    my $test = shift;

    $test->run_command($test->test_command);

    copy($fg, $ft) or die "Cannot copy $fg to $ft: $!";

    $test->{test_parameters} .= " -merge 1";
    $test->run_command($test->test_command);
}

copy($fg, $ft) or die "Cannot copy $fg to $ft: $!";

open T, ">>$ft" or die "Cannot open $ft: $!";
print T "# blah blah\n";
close T  or die "Cannot close $ft: $!";

my $test = Devel::Cover::Test->new
(
    $t,
    golden_test => $g,
    run_test    => \&run_test,
    changes     => "s/$t/$g    /;  " .
                   "s/$g\\s+\$/$g/;" .
                   'if (/^Run: /) { $get_line->() for 1 .. 5; redo }' .
                   "redo if /Deleting old coverage for changed file/",
    tests       => sub { $_[0] - 6 },
);

$test->run_test;

unlink $ft

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# The test_options and cover_parameters subcommands build option strings for
# the Makefile _run and cover targets from __COVER__ directives in test files.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is like )];

my $Dir = tempdir(CLEANUP => 1);
my $N   = 0;

sub write_test ($content) {
  my $path = "$Dir/test" . $N++;
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
  $path
}

sub makeh (@args) {
  qx($^X utils/makeh @args 2>&1)
}

my $Plain = write_test("print 1;\n");
is makeh(test_options     => $Plain), "-coverage,all", "no directives";
is makeh(cover_parameters => $Plain), "",              "no directives";

my $Criteria
  = write_test("# __COVER__ criteria statement branch condition subroutine\n");
is makeh(test_options => $Criteria),
  "-coverage,statement,branch,condition,subroutine",
  "criteria words become a comma-separated list";

my $Pod = write_test("# __COVER__ criteria pod-also_private-xx\n");
is makeh(test_options => $Pod), "-coverage,pod-also_private-xx",
  "single criteria word";

my $Params = write_test("# __COVER__ test_parameters -subs_only,1\n");
is makeh(test_options => $Params), "-subs_only,1,-coverage,all",
  "test_parameters precede coverage";

my $Ignore = write_test("# __COVER__ cover_parameters -ignore_covered_err\n");
is makeh(cover_parameters => $Ignore), "-ignore_covered_err",
  "cover_parameters";

my $Both
  = write_test("# __COVER__ cover_parameters -ignore_covered_err\n"
    . "# __COVER__ test_parameters -subs_only,1\n"
    . "# __COVER__ criteria statement branch\n");
is makeh(test_options => $Both), "-subs_only,1,-coverage,statement,branch",
  "combined directives, test_options";
is makeh(cover_parameters => $Both), "-ignore_covered_err",
  "combined directives, cover_parameters";

like makeh(test_options => "$Dir/missing"), qr/^Cannot open /,
  "unreadable file is reported";
like makeh(bogus => $Plain), qr/^No such command: bogus/, "unknown command";

done_testing

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", qw( ./lib ./blib/lib ./blib/arch ./t );

use Test::More import => [qw( done_testing like )];

use Devel::Cover::Test ();

sub main () {
  my $test = Devel::Cover::Test->new(
    "e2e_cover_command_selftest",
    run_test         => sub { },
    cover_parameters => ["-silent"],
  );

  like $test->cover_command, qr/ -silent -nogcov -report text /,
    "e2e tests run cover without the gcov search";

  rmdir "./t/e2e/cover_db_e2e_cover_command_selftest";
}

main;
done_testing;

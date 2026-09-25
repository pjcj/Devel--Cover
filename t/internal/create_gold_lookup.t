#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# A fixture tests/foo becomes t/e2e/afoo.t and a hand-written tests/foo.t is
# copied to t/e2e/foo.t. When both exist the bare name foo must resolve to
# the fixture, or the fixture's golden file is never regenerated.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use File::Path qw( make_path );
use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is )];

chdir "$FindBin::Bin/../.." or die "Can't chdir to the project root: $!";
do "./utils/create_gold"    or die "Can't load create_gold: $@$!";

my $Dir = tempdir(CLEANUP => 1);
make_path "$Dir/t/e2e";
for my $name (qw( eval_merge.t aeval_merge.t sep.t )) {
  open my $fh, ">", "$Dir/t/e2e/$name" or die "Can't write $name: $!";
  close $fh or die "Can't close $name: $!";
}
chdir $Dir or die "Can't chdir to $Dir: $!";

is e2e_file("eval_merge"), "t/e2e/aeval_merge.t",
  "a bare name prefers the generated fixture test";
is e2e_file("eval_merge.t"), "t/e2e/eval_merge.t",
  "a .t name is the copied test";
is e2e_file("aeval_merge.t"), "t/e2e/aeval_merge.t",
  "a generated name is itself";
is e2e_file("sep"), "t/e2e/sep.t", "a bare name with only a .t test uses it";
is e2e_file("t/x/other.pl"), "t/x/other.pl", "an unknown name is unchanged";

done_testing;

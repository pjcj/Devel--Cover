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
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is ok )];

use Devel::Cover::Test::Showcase qw( slurp );

# $Latest_released_perl decides which development versions are obsolete, so it
# must track the newest stable perl the project builds against. Take that from
# utils/all_versions, which the perl version update process already maintains.

my $Root = "$FindBin::Bin/../..";

sub main () {
  my @stable = grep !($_ % 2),
    slurp("$Root/utils/all_versions") =~ /\b5\.(\d+)\.\d+/g;
  ok @stable, "found stable versions in utils/all_versions";

  my ($latest)
    = slurp("$Root/t/lib/Devel/Cover/Test.pm")
    =~ /^my \$Latest_released_perl = (\d+);$/m;
  ok defined $latest, 'found $Latest_released_perl in Devel::Cover::Test';

  my ($newest) = sort { $b <=> $a } @stable;
  is $latest, $newest,
    "\$Latest_released_perl tracks the newest stable perl (5.$newest)";

  done_testing;
}

main;

#!/usr/bin/perl

# Copyright 2012-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use List::Util qw( any );
use Test::More import => [qw( ok plan )];

opendir my $d, "lib/Devel/Cover/Report";
my @Reporters = map { s/\.pm$//r } grep /\.pm$/, readdir $d;
closedir $d;

{
  local $SIG{__WARN__} = sub { };
  eval "use HTML::Entities; 1";
  if ($@) {
    plan skip_all => "No HTML::Entities";
    exit;
  }
}

plan tests => scalar @Reporters;

my @Reporters_with_launch = qw(
  Html Html_basic Html_crisp Html_minimal Html_subtle
);

# Check that the expected reporters support the launch feature
for my $reporter (@Reporters) {
  my $class = "Devel::Cover::Report::" . $reporter;
  eval "require $class";

  if (any { $_ eq $reporter } @Reporters_with_launch) {
    ok($class->can("launch"), "$reporter supports launch");
  } else {
    ok(!$class->can("launch"), "$reporter does not support launch");
  }
}

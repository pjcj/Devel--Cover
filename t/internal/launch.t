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
use Test::More import => [qw( diag done_testing note ok plan )];

my @Reporters_with_launch = qw(
  Html Html_basic Html_crisp Html_minimal Html_subtle
);

sub read_reporters () {
  opendir my $d, "lib/Devel/Cover/Report";
  my @reporters = map s/\.pm$//r, grep /\.pm$/, readdir $d;
  closedir $d;
  @reporters
}

sub test_launch_list ($reporters) {
  for my $launcher (@Reporters_with_launch) {
    ok grep($_ eq $launcher, @$reporters), "$launcher is a reporter";
  }
}

sub load_reporter ($class) {
  my $loaded = eval "require $class; 1";
  my $err    = $@;

  # An earlier failed load leaves a stale %INC entry for a shared module
  while (!$loaded && $err =~ m|^Attempt to reload (\S+\.pm) aborted|) {
    delete $INC{$1};
    $loaded = eval "require $class; 1";
    $err    = $@;
  }

  ($loaded, $err)
}

sub test_reporter_launch ($reporter) {
  my $class = "Devel::Cover::Report::" . $reporter;
  my ($loaded, $err) = load_reporter($class);

  if (!$loaded && $err =~ m|^Can't locate (\S+\.pm) in \@INC|) {
    my $missing = $1;
    if ($missing !~ m|^Devel/Cover/|) {
      note "skipping $reporter: missing optional prerequisite $missing";
      return;
    }
  }

  ok $loaded, "$reporter loads" or diag $err;
  return unless $loaded;

  if (any { $_ eq $reporter } @Reporters_with_launch) {
    ok $class->can("launch"), "$reporter supports launch";
  } else {
    ok !$class->can("launch"), "$reporter does not support launch";
  }
}

sub main () {
  {
    local $SIG{__WARN__} = sub { };
    eval "use HTML::Entities; 1";
    if ($@) {
      plan skip_all => "No HTML::Entities";
      exit;
    }
  }

  my @reporters = read_reporters;
  test_launch_list(\@reporters);
  test_reporter_launch($_) for @reporters;
  done_testing;
}

main;

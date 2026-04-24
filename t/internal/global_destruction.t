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

use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing is )];

# Regression test for GH-464.  During Perl's DESTRUCT phase, some of the
# anonymous qr// bodies held by Devel::Cover's module-scoped arrays (@Inc_re,
# @Ignore_re, @Select_re) may be freed before the arrays themselves.  If
# coverage code runs during DESTRUCT (e.g. a DESTROY handler does `require
# Some::Module`), the four loops that match paths against those arrays see undef
# slots and emit warnings like "Use of uninitialized value $_ in regexp
# compilation ... during global destruction".

# The effect is non-deterministic; SV cleanup order is not fixed.  We require
# Time::Local during DESTROY and run the reproducer many times. Time::Local is
# chosen deliberately: empirically it has a ~55% hit rate per run on Perl
# 5.42.2, whereas a trivial inline test module (even one with many subs or a
# cascade of `use` statements) has a 0% hit rate.  The difference appears to be
# down to SV-cleanup ordering rather than anything we can synthesise locally, so
# rather than ship a bespoke trigger module that might not trigger, we depend on
# Time::Local - a core module since Perl 5.0 and therefore always present on the
# 5.20+ that Devel::Cover supports.  With 30 iterations the pre-fix false-green
# probability is ~ 0.45 ** 30, i.e. ~ 4e-11.

sub test_no_uninitialized_warning_during_global_destruction () {
  my $tmpdir = tempdir(CLEANUP => 1);

  my $script = File::Spec->catfile($tmpdir, "destruct.pl");
  open my $fh, ">", $script or die "write $script: $!";
  print $fh <<'EOS';
package Guard;
sub DESTROY { require Time::Local }
package main;
our $g = bless {}, "Guard";
print "done\n";
EOS
  close $fh or die "close $script: $!";

  my $iterations = 30;
  my @failures;
  for my $i (1 .. $iterations) {
    my $db  = File::Spec->catdir($tmpdir, "cover_db_$i");
    my $cmd = join " ", map qq("$_"), $^X, "-Mblib",
      "-MDevel::Cover=-silent,1,-db,$db", $script;
    my $output = `$cmd 2>&1`;
    push @failures, "iter $i: $output"
      if $output =~ /uninitialized.*global destruction/s;
  }

  is scalar @failures, 0,
    "no uninitialized-value warnings across $iterations iterations"
    or diag join "\n---\n", @failures[0 .. ($#failures < 2 ? $#failures : 2)];
}

sub main () {
  test_no_uninitialized_warning_during_global_destruction;
  done_testing;
}

main;

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();  ## no perlimports
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is ok plan )];

BEGIN {
  plan skip_all => "Devel::Cover::Collection requires Perl 5.42" if $] < 5.042;
  plan skip_all => "Devel::Cover::Collection is not portable to Windows"
    if $^O eq "MSWin32";
  for my $module (qw( Template Parallel::Iterator JSON::MaybeXS )) {
    plan skip_all => "$module required for this test"
      unless eval "require $module; 1";
  }
}

use Devel::Cover::Collection ();

my $C = Devel::Cover::Collection->new;

sub test_zero_versions () {
  ok !$C->_newer("0.0", "0"),   "equal zero versions are not newer";
  ok !$C->_newer("0",   "0.0"), "equal zero versions are not newer reversed";
  ok $C->_newer("1.2",  "0"),   "a real version is newer than zero";
  ok !$C->_newer("0",   "1.2"), "zero is not newer than a real version";
}

sub test_parse_version () {
  my @parsed = $C->_parse_version("not a version!!");
  is @parsed, 1, "a failed parse still yields one result";
  ok !defined $parsed[0], "a failed parse yields undef";
}

sub test_numeric_compare () {
  ok $C->_newer("v1.10.0", "v1.9.0"), "versions compare numerically";
}

sub test_undef_versions () {
  my @warnings;
  {
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    ok !$C->_newer(undef, undef), "undef versions are not newer";
  }
  is "@warnings", "", "undef versions compare without warning";
}

sub main () {
  test_zero_versions;
  test_parse_version;
  test_numeric_compare;
  test_undef_versions;
}

main;
done_testing;

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# _parse_options must key list resets off the parsed option tokens, not a
# substring match against the space-joined option string, where a value such
# as "my-inc" can trigger a spurious reset.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use File::Spec ();
use File::Temp qw( tempdir );

use Test::More import => [qw( diag done_testing is_deeply ok )];

my $Tmpdir = File::Spec->rel2abs(tempdir(CLEANUP => 1));
my $N      = 0;

sub run_covered ($opts) {
  local $ENV{DEVEL_COVER_OPTIONS};
  local $ENV{DEVEL_COVER_SELF};
  local $ENV{DEVEL_COVER_DEBUG};
  delete @ENV{qw( DEVEL_COVER_OPTIONS DEVEL_COVER_SELF DEVEL_COVER_DEBUG )};

  my $db = File::Spec->catdir($Tmpdir, "db" . $N++);
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch"
    . " -MDevel::Cover=-db,$db,-merge,0,-summary,0,-silent,0,$opts"
    . " -e 1 2>&1";
  scalar `$cmd`
}

sub section ($out, $header) {
  my ($body) = $out =~ /^\Q$header\E\n((?:[ ]{4}.*\n)*)/m;
  [map s/^[ ]{4}//r, split /\n/, $body // ""]
}

sub test_value_ending_in_inc_keeps_defaults () {
  my $out = run_covered("-ignore,my-inc,-select,xyzzy");
  ok section($out, "Ignoring packages in:")->@* > 0,
    'a value ending in -inc does not empty the @INC list'
    or diag $out;
}

sub test_inc_option_replaces_defaults () {
  my $out = run_covered("-inc,/xyzzy");
  is_deeply section($out, "Ignoring packages in:"), ["/xyzzy"],
    '-inc replaces the default @INC list';
}

sub test_trailing_bare_inc_resets () {
  my $out = run_covered("-ignore,foo,-inc");
  is_deeply section($out, "Ignoring packages in:"), [],
    'a trailing bare -inc still resets the @INC list';
}

sub test_plus_inc_appends () {
  my $out = run_covered("+inc,/xyzzy");
  my $inc = section($out, "Ignoring packages in:");
  ok grep($_ eq "/xyzzy", @$inc), "+inc appends the new path";
  ok @$inc > 1,                   '+inc keeps the default @INC list';
}

sub test_value_ending_in_ignore_keeps_defaults () {
  my $out    = run_covered("-select,my-ignore,-inc,/xyzzy");
  my $ignore = section($out, "Ignoring packages matching:");
  ok grep(m|/Devel/Cover|, @$ignore),
    "a value ending in -ignore does not drop the default ignore pattern"
    or diag $out;
}

sub main () {
  test_value_ending_in_inc_keeps_defaults;
  test_inc_option_replaces_defaults;
  test_trailing_bare_inc_resets;
  test_plus_inc_appends;
  test_value_ending_in_ignore_keeps_defaults;
  done_testing;
}

main;

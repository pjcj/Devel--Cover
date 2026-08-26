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

use Test::More import => [qw( diag done_testing is is_deeply isa_ok )];

use Devel::Cover::DB           ();
use Devel::Cover::Report::Text ();

sub db_with_runs (%runs) {
  Devel::Cover::DB->new(runs => {%runs}, _structure => 0)
}

sub test_undef_runs_removed () {
  my $db = db_with_runs(r1 => undef, r2 => undef);
  $db->cover;
  is keys $db->{runs}->%*, 0, "undef runs are deleted from the database";
}

sub test_single_undef_run_removed () {
  my $db = db_with_runs(r1 => undef);
  $db->cover;
  is keys $db->{runs}->%*, 0, "a single undef run is deleted";
}

sub test_mixed_runs_keep_real_run () {
  my $db = db_with_runs(
    r1 => undef,
    r2 => { start => 100, collected => ["statement"] },
  );
  $db->cover;
  is_deeply [keys $db->{runs}->%*], ["r2"], "only the real run survives";
  isa_ok $db->{runs}{r2}, "Devel::Cover::DB::Run";
}

sub test_print_runs_silent_after_cover () {
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_ };
  my $db = db_with_runs(r1 => undef, r2 => undef);
  $db->cover;
  my $output;
  {
    open my $fh, ">", \$output or die "Cannot open scalar ref: $!";
    local *STDOUT = $fh;
    Devel::Cover::Report::Text::print_runs($db, undef);
    close $fh or die "Cannot close scalar ref: $!";
  }
  is $output // "", "", "no run blocks printed for undef runs";
  is @warnings, 0, "no warnings printing a database of undef runs"
    or diag join "", @warnings;
}

sub main () {
  test_undef_runs_removed;
  test_single_undef_run_removed;
  test_mixed_runs_keep_real_run;
  test_print_runs_silent_after_cover;
  done_testing;
}

main;

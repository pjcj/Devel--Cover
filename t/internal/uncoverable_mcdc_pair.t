#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# "# uncoverable mcdc pair:N" is 1-based.  pair:0 and columns past the
# decision's width must warn and be ignored, never abort the report (GH-496).
# The warnings go through dcwarn, so -silent suppresses them.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is is_deeply like ok )];

use Devel::Cover::DB ();

my $Tmpdir = tempdir(CLEANUP => 1);

{
  no feature "signatures";

  # Warnings go to STDERR via dcwarn, not through perl's warn.
  sub warnings_from (&) {
    my ($code) = @_;
    my $err = "";
    open my $save_err, ">&", \*STDERR or die "Cannot dup STDERR: $!";
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">", \$err or die "Cannot redirect STDERR: $!";
    $code->();
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">&", $save_err or die "Cannot restore STDERR: $!";
    [split /(?<=\n)/, $err]
  }
}

sub parse_comments ($source) {
  my $path = File::Spec->catfile($Tmpdir, "source.pl");
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $source;
  close $fh or die "Cannot close $path: $!";

  my $unc      = {};
  my $warnings = warnings_from {
    Devel::Cover::DB->new->uncoverable_comments($unc, $path, "digest");
  };
  ($unc, $warnings, $path)
}

sub test_pair_zero_is_rejected () {
  my ($unc, $warnings, $path) = parse_comments(<<'PERL');
my ($a, $b) = (1, 1);
# uncoverable mcdc pair:0
my $r = $a && $b;
PERL
  is @$warnings, 1, "pair:0: one warning";
  like $warnings->[0], qr/\bpair:0\b/,  "pair:0: warning names the marker";
  like $warnings->[0], qr/\Q$path\E:2/, "pair:0: warning gives file:line";
  ok !exists $unc->{digest}{mcdc}, "pair:0: marker is ignored";
}

sub test_pair_one_is_recorded () {
  my ($unc, $warnings) = parse_comments(<<'PERL');
my $always = 1;
# uncoverable mcdc pair:1
my $r = $always && $b;
PERL
  is @$warnings, 0, "pair:1: no warnings";
  is_deeply $unc->{digest}{mcdc}{3}, [[[0, "default", ""]]],
    "pair:1: column 0 marked";
}

sub mcdc_uncoverable ($marks, $total) {
  my $uncov;
  my $warnings = warnings_from {
    $uncov = do {

      package Devel::Cover::DB;
      _mcdc_uncoverable({ 7 => [$marks] }, "source.pl", 7, 0, $total)
    };
  };
  ($uncov, $warnings)
}

sub test_out_of_range_column_warns () {
  my ($uncov, $warnings) = mcdc_uncoverable([[5, "default", ""]], 2);
  is @$warnings, 1, "pair:6: one warning";
  like $warnings->[0], qr/\bpair:6\b/,   "pair:6: warning names the marker";
  like $warnings->[0], qr/source\.pl:7/, "pair:6: warning gives file:line";
  ok !(grep defined, @$uncov), "pair:6: no column marked";
}

sub test_negative_column_warns () {
  my ($uncov, $warnings) = mcdc_uncoverable([[-1, "default", ""]], 2);
  is @$warnings, 1, "negative column: one warning";
  ok !(grep defined, @$uncov), "negative column: no column marked";
}

sub test_bare_marker_marks_all_columns () {
  my ($uncov, $warnings) = mcdc_uncoverable([[undef, "default", ""]], 2);
  is @$warnings, 0, "bare marker: no warnings";
  is_deeply $uncov, ["default", "default"], "bare marker: every column marked";
}

sub test_pair_zero_warning_respects_silent () {
  local $Devel::Cover::Silent = 1;
  my ($unc, $warnings) = parse_comments(<<'PERL');
my ($a, $b) = (1, 1);
# uncoverable mcdc pair:0
my $r = $a && $b;
PERL
  is @$warnings, 0, "pair:0 silent: no warning";
  ok !exists $unc->{digest}{mcdc}, "pair:0 silent: marker still ignored";
}

sub test_out_of_range_warning_respects_silent () {
  local $Devel::Cover::Silent = 1;
  my ($uncov, $warnings) = mcdc_uncoverable([[5, "default", ""]], 2);
  is @$warnings, 0, "out of range silent: no warning";
  ok !(grep defined, @$uncov), "out of range silent: no column marked";
}

test_pair_zero_is_rejected;
test_pair_one_is_recorded;
test_out_of_range_column_warns;
test_negative_column_warns;
test_bare_marker_marks_all_columns;
test_pair_zero_warning_respects_silent;
test_out_of_range_warning_respects_silent;

done_testing;

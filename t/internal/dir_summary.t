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

use Devel::Cover::DB ();

sub crit ($covered, $total) {
  { covered => $covered, total => $total, error => $total - $covered }
}

sub test_all_criteria_aggregated () {
  my $db = bless {}, "Devel::Cover::DB";
  my $s  = {
    "lib/A/Foo.pm" => {
      statement  => crit(5, 10),
      branch     => crit(1, 4),
      condition  => crit(2, 6),
      mcdc       => crit(1, 3),
      subroutine => crit(2, 2),
      pod        => crit(1, 2),
      time       => { covered => 0, total => 123, error => 0 },
      total      => crit(12, 27),
      complexity => { max     => 3, mean     => 2, count => 2 },
      scar       => { file_cc => 4, file_cov => 50 },
    },
    "lib/A/Bar.pm" => {
      statement  => crit(10, 10),
      subroutine => crit(1,  2),
      total      => crit(11, 12),
    },
  };
  my $dir_files = { "lib/A" => ["lib/A/Foo.pm", "lib/A/Bar.pm"] };
  my $dir_stats = { "lib/A" => { cc_sum => 6, cc_count => 3 } };

  $db->_summarise_dir_complexity($s, $dir_files, $dir_stats);

  my $d = $db->dir_summary("lib/A");
  ok $d, "directory summary created";
  is $d->{statement}{covered},    15, "statement covered summed";
  is $d->{statement}{total},      20, "statement total summed";
  is $d->{statement}{percentage}, 75, "statement percentage computed";
  is $d->{branch}{total},         4,  "branch aggregated";
  is $d->{condition}{total},      6,  "condition aggregated";
  is $d->{mcdc}{total},           3,  "mcdc aggregated";
  is $d->{subroutine}{covered},   3,  "subroutine aggregated";
  is $d->{pod}{covered},          1,  "pod aggregated";
  is $d->{total}{covered},        23, "total aggregated";
  ok !exists $d->{time},       "time not aggregated";
  ok !exists $d->{complexity}, "complexity not treated as a criterion";
  is $d->{scar}{file_cc}, 4, "dir SCAR computed from dir stats";
}

sub main () {
  test_all_criteria_aggregated;
  done_testing;
}

main;

#!/usr/local/bin/perl

# Copyright 2001, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

use Devel::Cover::Process 0.01 qw( cover_read );
use Devel::Cover 0.01 qw( -i 1 -o t1.cov );

use strict;
use warnings;

use Test;

BEGIN { plan tests => 3 }

use lib -d "t" ? "t" : "..";

use T1;

my @x;

sub xx
{
  $x[shift]++;
  T1::zz(0);
}

for (0 .. 1000)
{
  time &&
    $x[1]++;

  $x[2]++
    if time;

  for (0 .. 2)
  {
      $x[3]++;
  }

  if (time)
  {
    xx(4);
  }
  else
  {
    $x[5]++;
  }
}

Devel::Cover::report();

END
{
    ok open T1, "t1.cov";
    my $t1 = cover_read(*T1{IO});
    my $t2 = cover_read(*DATA{IO});
    ok close T1;
    my $error = "keys";
    my $ok = keys %$t1 == keys %$t2;
    FILE:
    for my $file (sort keys %$t1)
    {
        $error = "file $file";
        my $f1 = $t1->{$file};
        my $f2 = delete $t2->{$file};
        last FILE unless $ok &&= $f2;
        $ok &&= keys %$f1 == keys %$f2;
        for my $line (sort keys %$f1)
        {
            $error = "file $file line $line";
            my $l1 = $f1->{$line};
            my $l2 = delete $f2->{$line};
            last FILE unless $ok &&= $l2;
            $ok &&= @$l1 == @$l2;
            for my $c1 (@$l1)
            {
                my $c2 = shift @$l2;
                $error = "file $file line $line $c1 != $c2";
                last FILE unless $ok &&= !($c1 xor $c2);
            }
        }
    }
    ok $ok ? "done" : "mismatch at $error", "done";
}

__DATA__
$cover = {
  't/t1.t' => {
    '29' => [
      1001
    ],
    '45' => [
      1001
    ],
    '37' => [
      1001
    ],
    '55' => [
      1
    ],
    '24' => [
      2
    ],
    '32' => [
      1,
      1001
    ],
    '40' => [
      1001,
      3003
    ],
    '42' => [
      3003
    ],
    '35' => [
      1002
    ],
    '51' => [
      0
    ],
    '28' => [
      1006
    ]
  },
  't/T1.pm' => {
    '13' => [
      1001
    ],
    '12' => [
      1001
    ]
  }
};

#!/usr/local/bin/perl

# Copyright 2001, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

use Devel::Cover::Process 0.05 qw( cover_read );
use Devel::Cover 0.05 qw( -indent 1 -output t1.cov );

use strict;
use warnings;

use Test;

BEGIN { plan tests => 1 }

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
    my $t1 = Devel::Cover::Process->new(file       => "t1.cov" )->cover;
    my $t2 = Devel::Cover::Process->new(filehandle => *DATA{IO})->cover;
    my $error = "files";
    my $ok = keys %$t1 == keys %$t2;
    FILE:
    for my $file (sort keys %$t1)
    {
        $error = "$file";
        my $f1 = $t1->{$file};
        my $f2 = delete $t2->{$file};
        last FILE unless $ok &&= $f2;
        $ok &&= keys %$f1 == keys %$f2;
        for my $criterion (sort keys %$f1)
        {
            $error = "$file $criterion";
            my $c1 = $f1->{$criterion};
            my $c2 = delete $f2->{$criterion};
            last FILE unless $ok &&= $c2;
            for my $line (sort keys %$c1)
            {
                $error = "$file $criterion $line";
                my $l1 = $c1->{$line};
                my $l2 = delete $c2->{$line};
                last FILE unless $ok &&= $l2;
                $ok &&= @$l1 == @$l2;
                for my $v1 (@$l1)
                {
                    my $v2 = shift @$l2;
                    $error = "$file $criterion $line $v1 != $v2";
                    last FILE unless $ok &&= !($v1 xor $v2);
                }
                $error = "$file $criterion $line extra";
                last FILE unless $ok &&= !@$l2;
            }
            $error = "$file $criterion extra";
            last FILE unless $ok &&= !keys %$c2;
        }
        $error = "$file extra";
        last FILE unless $ok &&= !keys %$f2;
    }
    $error = "extra" unless $ok &&= !keys %$t2;
    ok $ok ? "done" : "mismatch: $error", "done";
}

__DATA__

$cover = {
  't/T1.pm' => {
    'statement' => {
      '13' => [
        1001
      ],
      '12' => [
        1001
      ]
    }
  },
  't/t1.t' => {
    'statement' => {
      '35' => [
        1001
      ],
      '32' => [
        1,
        1001
      ],
      '28' => [
        1001
      ],
      '40' => [
        1001,
        3003
      ],
      '51' => [
        0
      ],
      '47' => [
        1001
      ],
      '42' => [
        3003
      ],
      '24' => [
        4
      ],
      '37' => [
        1001
      ],
      '45' => [
        1001
      ],
      '29' => [
        1002
      ],
      '55' => [
        1
      ]
    },
    'condition' => {
      '35' => [
        [
          1001,
          1001
        ]
      ],
      '32' => [
        [
          1002,
          0
        ]
      ],
      '40' => [
        [
          4004,
          0
        ]
      ],
      '37' => [
        [
          1001,
          1001
        ]
      ],
      '51' => [
        [
          1001,
          0,
          0
        ]
      ]
    }
  }
};

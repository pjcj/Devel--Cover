#!/usr/local/bin/perl

# Copyright 2001, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

use strict;
use warnings;

use Devel::Cover::DB 0.07;
use Devel::Cover 0.07 qw( -db t2 -indent 1 -merge 0 );

use Test;

BEGIN { plan tests => 1 }

use lib -d "t" ? "t" : "..";

eval <<EOS;
sub e
{
    1
}
EOS
e();

Devel::Cover::report();

END
{
    require Compare;
    ok Compare::compare("t2", *DATA{IO}), "done";
}

__DATA__

$cover = {
  't/t2.t' => {
    'statement' => {
      '22' => [
        3,
        1
      ],
      '28' => [
        1
      ],
      '30' => [
        1
      ]
    }
  }
};

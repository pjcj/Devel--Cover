# Copyright 2001, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Compare;

use strict;
use warnings;

our $VERSION = "0.10";

sub compare
{
    my ($results, $golden) = @_;
    my $t1 = Devel::Cover::DB->new(db         => $results )->cover;
    my $t2 = Devel::Cover::DB->new(filehandle => $golden  )->cover;
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
    $ok ? "done" : "mismatch: $error"
}

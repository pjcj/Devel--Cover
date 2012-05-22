# Copyright 2002-2012, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package NotModule2;

my $y = 7;
$y++;

sub _aa
{
    $y++;
    die;
    die;
}

sub _xx
{
    $y++;
    die;
}

sub yy
{
    $y++;
}

sub zz
{
    my $x = shift;
    $x++;
}

1

__END__

=head2 yy

yy

=cut

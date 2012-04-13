# This file is part of Devel::Cover.

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

# Author of this file: Olivier Mengué

package  # Private module
   Devel::Cover::Dumper;

use strict qw<vars subs>; # no refs
use warnings;

sub import
{
    my $caller = caller;
    if (defined &{"${caller}::Dumper"} && \&{"${caller}::Dumper"} != \&Dumper) {
        require Carp;
        Carp::croak("Data::Dumper previously imported. Use instead Devel::Cover::Dumper");
    }
    *{"${caller}::Dumper"} = \&Dumper;
}

sub Dumper
{
    require Data::Dumper;
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Sortkeys = 1;
    Data::Dumper::Dumper(@_);
}

1;
__END__
# vim:set et:

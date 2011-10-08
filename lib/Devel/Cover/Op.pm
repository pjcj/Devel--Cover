# Copyright 2001-2011, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Op;

require 5.8.0;  # My patches to B::Concise didn't get released till 5.8.0.

use strict;
use warnings;

use Data::Dumper; $Data::Dumper::Indent = 1; $Data::Dumper::Sortkeys = 1;

use Devel::Cover qw( -ignore blib -ignore \\wB\\w );
use B::Concise   qw( set_style add_callback );

my %style =
  ("terse" =>
   ["(?(#label =>\n)?)(*(    )*)#class (#addr) #name <#cover> (?([#targ])?) "
    . "#svclass~(?((#svaddr))?)~#svval~(?(label \"#coplabel\")?)\n",
    "(*(    )*)goto #class (#addr)\n",
    "#class pp_#name"],
   "concise" =>
   ["#hyphseq2 #cover12 (*(   (x( ;)x))*)<#classsym> "
    . "#exname#arg(?([#targarglife])?)~#flags(?(/#private)?)(x(;~->#next)x)\n",
    "  (*(    )*)     goto #seq\n",
    "(?(<#seq>)?)#exname#arg(?([#targarglife])?)"],
   "debug" =>
   ["#class (#addr)\n\tcover\t\t#cover\n\top_next\t\t#nextaddr\n\top_sibling\t#sibaddr\n\t"
    . "op_ppaddr\tPL_ppaddr[OP_#NAME]\n\top_type\t\t#typenum\n\top_seq\t\t"
    . "#seqnum\n\top_flags\t#flagval\n\top_private\t#privval\n"
    . "(?(\top_first\t#firstaddr\n)?)(?(\top_last\t\t#lastaddr\n)?)"
    . "(?(\top_sv\t\t#svaddr\n)?)",
    "    GOTO #addr\n",
    "#addr"],
  );

my @Options;

sub import
{
    my $class = shift;
    set_style(@{$style{concise}});
    for (@_)
    {
        /-(.*)/ && exists $style{$1}
            ? set_style(@{$style{$1}})
            : push @Options, $_;
    }

    my $final = 1;
    add_callback
    (
        sub
        {
            my ($h, $op, $format, $level) = @_;
            my $key = Devel::Cover::get_key($op);
            # print Dumper Devel::Cover::coverage unless $d++;
            if ($h->{seq})
            {
                my ($s, $b, $c) =
                  map Devel::Cover::coverage($final ? $final-- : 0)->{$_}{$key},
                      qw(statement branch condition);
                local $" = ",";
                no warnings "uninitialized";
                $h->{cover} = $s ? "s[$s]"  :
                              $b ? "b[@$b]" :
                              $c ? "c[@$c]" :
                              "";
            }
            else
            {
                $h->{cover} = "";
            }
        }
    );
}

END { B::Concise::compile(@Options)->() }

1

__END__

=head1 NAME

Devel::Cover::Op - B::Concise with coverage data

=head1 SYNOPSIS

 perl -Mblib -MDevel::Cover::Op prog [options]

=head1 DESCRIPTION

This module works as if calling B::Concise but also outputs coverage
information.  It's primary purpose is to aid in the development of Devel::Cover.

See comments in Cover.xs (especially set_conditional()) to aid in interpreting
the output.

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2001-2011, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

# Copyright 2001-2003, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Op;

use strict;
use warnings;

our $VERSION = "0.21";

use Devel::Cover qw( -ignore blib -ignore \\wB\\w -indent 1 );
use B::Concise   qw( set_style add_callback );

my %style =
  ("terse" =>
   ["(?(#label =>\n)?)(*(    )*)#class (#addr) #name <#cover> (?([#targ])?) "
    . "#svclass~(?((#svaddr))?)~#svval~(?(label \"#coplabel\")?)\n",
    "(*(    )*)goto #class (#addr)\n",
    "#class pp_#name"],
   "concise" =>
   ["#hyphseq2 #cover6 (*(   (x( ;)x))*)<#classsym> "
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
    add_callback
    (
        sub
        {
            my ($h, $op, $level, $format) = @_;
            $h->{cover} = $h->{seq}
                ? Devel::Cover::coverage()->{pack "I*", $h->{seqnum}} || "-"
                : ""
        }
    );

}

END { B::Concise::compile(@Options)->() }

1

# TODO - fix and document

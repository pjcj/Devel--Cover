# Copyright 2001, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Op;

use strict;
use warnings;

our $VERSION = "0.04";

use Devel::Cover qw(-inc B -indent 1 -details 1);

my @Options;

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

sub set_style
{
    my ($style) = @_;
    @ENV{qw(B_CONCISE_FORMAT B_CONCISE_GOTO_FORMAT B_CONCISE_TREE_FORMAT)} =
        @{$style{$style}};
}

sub import
{
    my $class = shift;
    @Options = ("-env");
    set_style("concise");
    for (@_)
    {
        /-(.*)/ && exists $style{$1}
            ? set_style($1)
            : push @Options, $_;
    }
    $ENV{B_CONCISE_SUB} = "Devel::Cover::Op::concise_op";
}

END { require B::Concise; B::Concise::compile(@Options)->() }

sub concise_op
{
    my ($h, $op, $level, $format) = @_;
    $h->{cover} = Devel::Cover::coverage()->{pack "I*", $$op} ||
                 ($h->{seq} ? "-" : "");
}

# Copyright 2001, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover;

use strict;
use warnings;

use DynaLoader ();

use Devel::Cover::Process 0.05;

our @ISA     = qw( DynaLoader );
our $VERSION = "0.05";

use B qw( class ppname main_root main_start main_cv svref_2object OPf_KIDS );
use Data::Dumper;

my  $Covering = 1;

my  $Indent   = 0;
my  $Output   = "default.cov";
my  $Summary  = 1;
my  $Details  = 0;

my  %Cover;
our $Cv;      # gets localised
my  @Todo;
my  %Done;
my  @Inc;

BEGIN { @Inc = @INC }

END { report() }

sub import
{
    my $class = shift;
    while (@_)
    {
        local $_ = shift;
        /^-indent/  && do { $Indent  = shift; next };
        /^-output/  && do { $Output  = shift; next };
        /^-inc/     && do { push @Inc, shift; next };
        /^-summary/ && do { $Summary = shift; next };
        /^-details/ && do { $Details = shift; next };
        warn __PACKAGE__ . ": Unknown option $_ ignored\n";
    }
}

sub cover
{
    ($Covering) = @_;
    set_cover($Covering > 0);
}

sub report
{
    return unless $Covering > 0;
    cover(-1);
    # print "Processing cover data\n@Inc\n";
    $Cv = main_cv;
    get_subs("main");
    INC:
    while (my ($name, $file) = each %INC)
    {
        for (@Inc) { next INC if $file =~ /^\Q$_/ }
        # print "$name => $file\n";
        $name =~ s/\.pm$//;
        $name =~ s/\//::/g;
        get_subs($name);
    }
    walk_sub($Cv, main_start);
    @Todo = sort {$a->[0] <=> $b->[0]} @Todo;

    walk_topdown(main_root) unless null(main_root);
    for my $sub (@Todo)
    {
        my $name = $sub->[1]->SAFENAME;
        # print "$name\n";
        local $Cv = $sub->[1]->CV;
        walk_topdown($Cv->ROOT);
    }

    for my $file (sort keys %Cover)
    {
        for (@Inc) { delete $Cover{$file}, last if $file =~ /^\Q$_/ }
    }

    {
        local $Data::Dumper::Indent = $Indent;
        open OUT, ">$Output" or die "Cannot open $Output\n";
        print OUT Data::Dumper->Dump([\%Cover], ["cover"]);
        close OUT or die "Cannot close $Output\n";
    }

    my $cover = Devel::Cover::Process->new(cover => \%Cover);
    $cover->print_summary if $Summary;
    $cover->print_details if $Details;
}

my ($F, $L) = ("", 0);
my $Level = 0;

sub walk_topdown
{
    my ($op) = @_;
    my $class = class($op);
    my $cover = coverage()->{pack "I*", $$op};

    $Level++;

    # Statement coverage.

    if ($class eq "COP")
    {
        push @{$Cover{$F = $op->file}{statement}{$L = $op->line}}, $cover || 0
    }
    elsif (!null($op) &&
           $op->name eq "null"
           && ppname($op->targ) eq "pp_nextstate")
    {
        # If the current op is null, but it was nextstate, we can still
        # get at the file and line number, but we need to get dirty.

        $cover = coverage()->{pack "I*", ${$op->sibling}};
        my $o = $op;
        bless $o, "B::COP";
        push @{$Cover{$F = $o->file}{statement}{$L = $o->line}}, $cover || 0
    }

    # print " " x ($Level * 2), "$F:$L ", $op->name, ":$class\n";

    # Condition coverage.

    if ($op->can("flags") && ($op->flags & OPf_KIDS))
    {
        my $c;
        for (my $kid = $op->first; $$kid; $kid = $kid->sibling)
        {
            my $cov = walk_topdown($kid);
            push @$c, $cov || 0 if $class eq "LOGOP";
        }
        push @{$Cover{$F}{condition}{$L}}, $c if $c;
    }

    if ($class eq "PMOP" && ${$op->pmreplroot})
    {
        walk_topdown($op->pmreplroot);
    }

    $Level--;

    $class eq "LISTOP" ? undef : $cover
}

sub find_first
{
    my ($op) = @_;
    my $c = coverage()->{pack "I*", $$op};
    return $c if defined $c;
    for (my $kid = $op->first; $$kid; $kid = $kid->sibling)
    {
        if ($op->can("flags") && ($op->flags & OPf_KIDS))
        {
            my $c = find_first($kid);
            return $c if defined $c;
        }
    }
    undef
}

sub get_subs
{
    my $pack = shift;
    # print "package $pack\n";

    my %stash;
    { no strict 'refs'; %stash = svref_2object(\%{$pack . "::"})->ARRAY }
    $pack = ($pack eq "main") ? "" : $pack . "::";

    while (my ($key, $val) = each %stash)
    {
        if (class($val) eq "GV" && class($val->CV) ne "SPECIAL")
        {
            next if $Done{$$val}++;
            todo($val, $val->CV);
            walk_sub($val->CV);
        }
    }
}

sub null
{
    class(shift) eq "NULL";
}

sub is_state
{
    my $name = $_[0]->name;
    $name eq "nextstate" || $name eq "dbstate" || $name eq "setstate";
}

sub todo
{
    my($gv, $cv) = @_;
    my $seq = (!null($cv->START) && is_state($cv->START))
        ? $cv->START->cop_seq
        : 0;
    push @Todo, [$seq, $gv];
}

sub walk_sub
{
    my $cv = shift;
    local $Cv = $cv;
    my $op = $cv->ROOT;
    $op = shift if null($op);
    walk_tree($op) if $op && !null($op);
}

sub walk_tree
{
    my ($op) = @_;

    if ($op->name eq "gv")
    {
        my $gv = class($op) eq "PADOP"
                     ? (($Cv->PADLIST->ARRAY)[1]->ARRAY)[$op->padix]
                     : $op->gv;
        if ($op->next->name eq "entersub")
        {
            return if $Done{$$gv}++;
            return if class($gv->CV) eq "SPECIAL";
            todo($gv, $gv->CV);
            walk_sub($gv->CV);
        }
    }

    if ($op->flags & OPf_KIDS)
    {
        for (my $kid = $op->first; !null($kid); $kid = $kid->sibling)
        {
            walk_tree($kid);
        }
    }
}

bootstrap Devel::Cover $VERSION;

1;

__END__

=head1 NAME

Devel::Cover - Code coverage metrics for Perl

=head1 SYNOPSIS

  perl -MDevel::Cover prog args
  perl -MDevel::Cover=-output,prog.cov,-indent,1,-details,1 prog args

=head1 DESCRIPTION

This module provides code coverage metrics for Perl.

If you can't guess by the version number this is an alpha release.

Code coverage data are collected using a plugable runops function which
counts how many times each op is executed.  These data are then mapped
back to reality using the B compiler modules.

At the moment, only statement coverage and condition coverage
information is reported.  Coverage data for other metrics are collected,
but not reported.  Coverage data for some metrics are not yet collected.

You may find that the results don't match your expectations.  I would
imagine that at least one of them is wrong.

Requirements:
  Perl 5.6.1 or 5.7.1.
  The ability to compile XS extensions.

=head1 OPTIONS

 -indent indent - Set indentation level to indent. See Data::Dumper for details.
 -output file   - Send output to file (default default.cov).
 -inc path      - Prefix of files to ignore (default @INC).
 -summary val   - Print summary information iff val is true (default on).
 -details val   - Print detailed information iff val is true (default off).

=head1 TUTORIAL

Here's part of a message I sent to perl-qa about code coverage metrics.

=head2 1.0 Introduction

It is wise to remember the following quote from Dijkstra, who said:

  Testing never proves the absence of faults, it only shows their presence.

In particular, code coverage is just one weapon in the software engineer's
testing arsenal.

Any discussion of code coverage metrics is hampered by the fact that
many authors use different terms to describe the same kind of coverage.
Here, I shall provide only a brief introduction to some of the most
common metrics.

=head2 2.0 Metrics

=head2 2.1 Statement coverage

This is the most basic form of code coverage.  A statement is covered if
it is executed.  Note that statement != line of code.  Multiple
statements on a single line can confuse issues - the reporting if
nothing else.

Where there are sequences of statements without branches it is not
necessary to count the execution of every statement, just one will
suffice, but people often like the count of every line to be reported,
especially in summary statistics.  However it is not clear to me that
this is actually useful.

This type of coverage is fairly weak in that even with 100% statement
coverage there may still be serious problems in a program which could be
discovered through other types of metric.

It can be quite difficult to achieve 100% statement coverage.  There may
be sections of code designed to deal with error conditions, or rarely
occurring events such as a signal received during a certain section of
code.  There may also be code that should never be executed:

  if ($param > 20)
  {
    die "This should never happen!";
  }

It can be useful to mark such code in some way and flag an error if it
is executed.

Statement coverage, or something very similar, can be called statement
execution, line, block, basic block or segment coverage.  I tend to
favour block coverage which does not attempt to extend its results to
each statement.

=head2 2.2 Branch coverage

The goal of branch coverage is to ensure that whenever a program can
jump, it jumps to all possible destinations.  The most simple example is
a complete if statement:

  if ($x)
  {
    print "a";
  }
  else
  {
    print "b";
  }

In such a simple example statement coverage is as powerful, but branch
coverage should also allow for the case where the else part is missing:

  if ($x)
  {
    print "a";
  }

Full coverage is only achieved here if $x is true on one occasion and
false on another.

100% branch coverage implies 100% statement coverage.

Branch coverage is also called decision or all edges coverage.

=head2 2.3 Path coverage

There are classes of errors that branch coverage cannot detect, such as:

  $h = undef;
  if ($x)
  {
    $h = { a => 1 };
  }
  if ($y)
  {
    print $h->{a};
  }

100% branch coverage can be achieved by setting ($x, $y) to (1, 1) and then
to (0, 0).  But if we have (0, 1) then things go bang.

The purpose of path coverage is to ensure that all paths through the
program are taken.  In any reasonably sized program there will be an
enormous number of paths through the program and so in practice the
paths can be limited to a single subroutine, if the subroutine is not
too big, or simply to two consecutive branches.

In the above example there are four paths which correspond to the truth
table for $x and $y.  To achieve 100% path coverage they must all be
taken.  Note that missing elses count as paths.

In some cases it may be impossible to achieve 100% path coverage:

  a if $x;
  b;
  c if $x;

50% path coverage is the best you can get here.

Loops also contribute to paths, and pose their own problems which I'll
ignore for now.

100% path coverage implies 100% branch coverage.

Path coverage and some of its close cousins, are also known as
predicate, basis path and LCSAJ (Linear Code Sequence and Jump)
coverage.

=head2 2.4 Expression coverage

When a boolean expression is evaluated it can be useful to ensure that
all the terms in the expression are exercised.  For example:

  a if $x || $y

The expression should be exercised with ($x, $y) set to (0, 0) (required
for branch coverage), (0, 1) and (1, 0) (to ensure that $x and $y are
independent) and possibly with (1, 1).

Expression coverage gets complicated, and difficult to achieve, as the
expression gets complicated.

Expressions which are not directly a part of a branching construct
should also be covered:

  $z = $x || $y;
  a if $z;

Expression coverage is also known as condition, condition-decision and
multiple decision coverage.

=head2 3.0 Other considerations

In order to get people to actually use code coverage it needs to be
simple to use.  It should also be simple to understand the results and
to rectify any problems thrown up.  Finally, if the overhead is too
great it won't get used either.

So there's a basic tutorial on code coverage, or at least my version of
it.  Typing a few of these terms into google will probably provide a
basis for future research.

=head1 ACKNOWLEDGEMENTS

Some code and ideas cribbed from:

 Devel::OpProf
 B::Concise
 B::Deparse

=head1 SEE ALSO

 Data::Dumper
 B

=head1 BUGS

Huh?

=head1 VERSION

Version 0.05 - 9th May 2001

=head1 LICENCE

Copyright 2001, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

# Copyright 2001, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover;

use strict;
use warnings;

use DynaLoader ();

use Devel::Cover::DB  0.10;
use Devel::Cover::Inc 0.10;

our @ISA     = qw( DynaLoader );
our $VERSION = "0.10";

use B qw( class ppname main_root main_start main_cv svref_2object OPf_KIDS );
# use B::Debug;

my  $Covering = 1;

my  $DB       = "cover_db";
my  $Details  = 0;
my  $Merge    = 1;
my  @Ignore;
my  @Inc;
my  $Indent   = 0;
my  @Select;
my  $Summary  = 1;

my  %Cover;
our $Cv;      # gets localised
my  @Todo;
my  %Done;

BEGIN { @Inc = @Devel::Cover::Inc::Inc }
# BEGIN { $^P =  0x02 | 0x04 | 0x100 }
BEGIN { $^P =  0x04 | 0x100 }

END { report() }

sub import
{
    my $class = shift;
    @Inc = () if "@_" =~ /-inc /;
    while (@_)
    {
        local $_ = shift;
        /^-db/      && do { $DB      = shift; next };
        /^-details/ && do { $Details = shift; next };
        /^-merge/   && do { $Merge   = shift; next };
        /^-indent/  && do { $Indent  = shift; next };
        /^-summary/ && do { $Summary = shift; next };
        /^-ignore/  && do { push @Ignore, shift while $_[0] !~ /^-/; next };
        /^[-+]inc/  && do { push @Inc,    shift while $_[0] !~ /^-/; next };
        /^-select/  && do { push @Select, shift while $_[0] !~ /^-/; next };
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

    # This array should hold the top level of each package, ie all code
    # which is not part of a subroutine.  main_root gets us the main
    # root (!), but TODO: something similar for other packages.
    my @roots = (main_root);

    INC:
    while (my ($name, $file) = each %INC)
    {
        # print "test $name => $file\n";
        for (@Select) { next INC if $file !~ /$_/    }
        for (@Ignore) { next INC if $file =~ /$_/    }
        for (@Inc)    { next INC if $file =~ /^\Q$_/ }
        # print "use  $name => $file\n";
        $name =~ s/\.pm$//;
        $name =~ s/\//::/g;
        push @roots, get_subs($name);
    }
    walk_sub($Cv, main_start);
    @Todo = sort {$a->[0] <=> $b->[0]} @Todo;

    for (@roots)
    {
        walk_topdown($_) unless null($_);
    }

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

    my $cover = Devel::Cover::DB->new(cover => \%Cover);
    my $existing;
    eval { $existing = Devel::Cover::DB->new(db => $DB) if $Merge };
    $cover->merge($existing) if $existing;
    $cover->indent($Indent);
    $cover->write($DB);
    $cover->print_summary if $Summary;
    $cover->print_details if $Details;
}

my ($F, $L) = ("", 0);
# my $Level = 0;

sub get_location
{
    my ($op) = @_;

    $F = $op->file;
    $L = $op->line;

    # If there's an eval, get the real filename.  Enabled from $^P & 0x100.

    ($F, $L) = ($1, $2) if $F =~/^\(eval \d+\)\[(.*):(\d+)\]/;

    # print STDERR "<$F> => ";
    $F =~ s/ \(autosplit into .*\)$//;
    # print STDERR "<$F>\n";

}

sub walk_topdown
{
    my ($op) = @_;
    my $class = class($op);
    my $cover = coverage()->{pack "I*", $$op};

    # $Level++;

    # Statement coverage.

    if ($class eq "COP")
    {
        get_location($op);
        push @{$Cover{$F}{statement}{$L}}, $cover || 0;
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
        get_location($o);
        push @{$Cover{$F}{statement}{$L}}, $cover || 0;
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

    # $Level--;

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

    my $stash;
    { no strict 'refs'; $stash = svref_2object(\%{$pack . "::"}) }
    my %stash = $stash->ARRAY;

    my $cv_outside;

    while (my ($key, $val) = each %stash)
    {
        if (class($val) eq "GV" && class($val->CV) ne "SPECIAL")
        {
            next if $Done{$$val}++;

            my $cv = $val->CV;
            todo($val, $cv);
            walk_sub($cv);

            # Trying to find the code in packages which is outside
            # subroutines.  TODO: make it work.
            unless ($cv_outside)
            {
                do
                {
                    $cv = $cv->OUTSIDE
                } while class($cv) eq "CV";
                unless (null($cv))
                {
                    # $cv_outside = $cv;
                }
            }
        }
    }

    $cv_outside || ()
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

1

__END__

=head1 NAME

Devel::Cover - Code coverage metrics for Perl

=head1 SYNOPSIS

 perl -MDevel::Cover prog args
 perl -MDevel::Cover=-db,cover_db,-indent,1,-details,1 prog args

=head1 DESCRIPTION

This module provides code coverage metrics for Perl.

If you can't guess by the version number this is an alpha release.

Code coverage data are collected using a plugable runops function which
counts how many times each op is executed.  These data are then mapped
back to reality using the B compiler modules.

The B<cover> program can be used to generate coverage reports.

At the moment, only statement coverage and condition coverage
information is reported.  Condition coverage data is not accurate at the
moment, but statement coverage data should be reasonable.  Coverage data
for other metrics are collected, but not reported.  Coverage data for
some metrics are not yet collected.

You may find that the results don't match your expectations.  I would
imagine that at least one of them is wrong.

Requirements:
  Perl 5.6.1 or 5.7.1.
  The ability to compile XS extensions.

=head1 OPTIONS

 -db cover_db   - Store results in coverage db (default cover_db).
 -details val   - Print detailed information iff val is true (default off).
 -inc path      - Set prefixes of files to ignore (default @INC).
 +inc path      - Append to prefixes of files to ignore.
 -ignore RE     - Ignore files matching RE.
 -indent indent - Set indentation level to indent. See Data::Dumper for details.
 -merge val     - Merge databases, for multiple test benches (default on).
 -select RE     - Only report on files matching RE.
 -summary val   - Print summary information iff val is true (default on).

=head1 ACKNOWLEDGEMENTS

Some code and ideas cribbed from:

 Devel::OpProf
 B::Concise
 B::Deparse

=head1 SEE ALSO

 Devel::Cover::Tutorial
 Data::Dumper
 B

=head1 BUGS

Huh?

=head1 VERSION

Version 0.10 - 27th August 2001

=head1 LICENCE

Copyright 2001, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

# Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover;

use strict;
use warnings;

our @ISA     = qw( DynaLoader );
our $VERSION = "0.15";

use DynaLoader ();

use Devel::Cover::DB  0.15;
use Devel::Cover::Inc 0.15;

use B qw( class ppname main_cv main_start main_root walksymtable OPf_KIDS );
use B::Debug;
use B::Deparse;

use Cwd ();

BEGIN { eval "use Pod::Coverage 0.06" }     # We'll use this if it is available.

my $DB      = "cover_db";                   # DB name.
my $Indent  = 0;                            # Data::Dumper indent.
my $Merge   = 1;                            # Merge databases.

my @Ignore;                                 # Packages to ignore.
my @Inc;                                    # Original @INC to ignore.
my @Select;                                 # Packages to select.

my $Pod     = $INC{"Pod/Coverage.pm"};      # Do pod coverage.

my $Summary = 1;                            # Output coverage summary.

my @Cvs;                                    # All the Cvs we want to cover.
my $Cv;                                     # Cv we are looking in.

my $Coverage;                               # Raw coverage data.
my $Cover;                                  # Coverage data.

my %Criteria;                               # Names of coverage criteria.
my %Coverage;                               # Coverage criteria to collect.

my $Cwd = Cwd::cwd();                       # Where we start from.

BEGIN { @Inc = @Devel::Cover::Inc::Inc }
# BEGIN { $^P =  0x02 | 0x04 | 0x100 }
BEGIN { $^P =  0x04 | 0x100 }

CHECK
{
    check_files();

    # reset_op_seq(main_root);
    # reset_op_seq($_->ROOT) for @Cvs;

    set_coverage(keys %Coverage);

    my @coverage = get_coverage();
    my $last = pop @coverage;
    print __PACKAGE__, " $VERSION: Collecting coverage data for ",
          join(", ", @coverage),
          @coverage ? " and " : "",
          "$last.\n",
          "Selecting packages matching:", join("\n    ", "", @Select), "\n",
          "Ignoring packages matching:",  join("\n    ", "", @Ignore), "\n",
          "Ignoring packages in:",        join("\n    ", "", @Inc),    "\n";
}

END { report() }

sub import
{
    my $class = shift;

    # print __PACKAGE__, ": Parsing options from [@_]\n";

    @Inc = () if "@_" =~ /-inc /;
    while (@_)
    {
        local $_ = shift;
        /^-db/       && do { $DB         = shift; next };
        /^-indent/   && do { $Indent     = shift; next };
        /^-merge/    && do { $Merge      = shift; next };
        /^-summary/  && do { $Summary    = shift; next };
        /^-coverage/ &&
            do { $Coverage{+shift} = 1 while @_ && $_[0] !~ /^[-+]/; next };
        /^-ignore/   &&
            do { push @Ignore,   shift while @_ && $_[0] !~ /^[-+]/; next };
        /^[-+]inc/   &&
            do { push @Inc,      shift while @_ && $_[0] !~ /^[-+]/; next };
        /^-select/   &&
            do { push @Select,   shift while @_ && $_[0] !~ /^[-+]/; next };
        warn __PACKAGE__ . ": Unknown option $_ ignored\n";
    }

    for my $c (Devel::Cover::DB->new->criteria)
    {
        my $func = "coverage_$c";
        no strict "refs";
        $Criteria{$c} = $func->();
    }

    %Coverage = map { $_ => 1 } qw(statement branch condition time)
         unless keys %Coverage;
}

sub cover_names_to_val
{
    my $val = 0;
    for my $c (@_)
    {
        if (exists $Criteria{$c})
        {
            $val |= $Criteria{$c};
        }
        elsif ($c eq "all" || $c eq "none")
        {
            my $func = "coverage_$c";
            no strict "refs";
            $val |= $func->();
        }
        else
        {
            warn __PACKAGE__ . qq(: Unknown coverage criterion "$c" ignored.\n);
        }
    }
    $val;
}

sub set_coverage
{
    set_criteria(cover_names_to_val(@_));
}

sub add_coverage
{
    add_criteria(cover_names_to_val(@_));
}

sub remove_coverage
{
    remove_criteria(cover_names_to_val(@_));
}

sub get_coverage
{
    return unless defined wantarray;
    my @names;
    my $val = get_criteria();
    for my $c (sort keys %Criteria)
    {
        push @names, $c if $val & $Criteria{$c};
    }
    return wantarray ? @names : "@names";
}

my ($F, $L) = ("", 0);

sub get_location
{
    my ($op) = @_;

    $F = $op->file;
    $L = $op->line;

    # If there's an eval, get the real filename.  Enabled from $^P & 0x100.

    ($F, $L) = ($1, $2) if $F =~ /^\(eval \d+\)\[(.*):(\d+)\]/;

    $F =~ s/ \(autosplit into .*\)$//;
    $F =~ s/^$Cwd\///;
}

sub use_file
{
    my ($file) = @_;
    $file = $1 if $file =~ /^\(eval \d+\)\[(.*):\d+\]/;
    $file =~ s/ \(autosplit into .*\)$//;
    my $files = \%Devel::Cover::Files;
    return $files->{$file} if exists $files->{$file};
    for (@Select) { return $files->{$file} = 1 if $file =~ /$_/      }
    for (@Ignore) { return $files->{$file} = 0 if $file =~ /$_/      }
    for (@Inc)    { return $files->{$file} = 0 if $file =~ /^\Q$_\// }
    $files->{$file} = -e $file;
    warn __PACKAGE__ . qq(: Can't find file "$file": ignored.\n)
        unless $files->{$file} || $file =~ /\(eval \d+\)/;
    $files->{$file}
}

sub B::GV::find_cv
{
    return unless ${$_[0]->CV};

    my $cv = $_[0]->CV;
    push @Cvs, $cv;

    if ($cv->PADLIST->can("ARRAY") &&
        $cv->PADLIST->ARRAY &&
        $cv->PADLIST->ARRAY->can("ARRAY"))
    {
        push @Cvs, grep class($_) eq "CV", $cv->PADLIST->ARRAY->ARRAY;
    }
};

sub check_files
{
    # print "Checking files\n";

    push @Cvs, grep class($_) eq "CV", B::main_cv->PADLIST->ARRAY->ARRAY;

    walksymtable(\%main::, "find_cv", sub { 1 }, "");

    for my $cv (@Cvs)
    {
        my $op = $cv->START;
        # print "$op\n";
        next unless $op->can("file") && class($op) ne "NULL" && is_state($op);

        my $file = $op->file;
        my $use  = use_file($file);
        # printf "%6s $file\n", $use ? "use" : "ignore";
    }

    # use Data::Dumper;
    # print Dumper \%Devel::Cover::Files;
}

sub report
{
    my @collected = get_coverage();
    return unless @collected;
    set_coverage("none");

    # print "Processing cover data\n@Inc\n";

    $Coverage = coverage() || die "No coverage data available.\n";

    # use Data::Dumper;
    # print Dumper $Coverage;

    get_cover(main_cv, main_root);
    for my $cv (@Cvs)
    {
        my $start = $cv->START;
        next unless $start->can("file") && use_file($start->file);
        # print "File: ", $start->file, "\n";
        get_cover($cv);
    }

    my $cover = Devel::Cover::DB->new
    (
        cover     => $Cover,
        collected => [ @collected ],
    );
    my $existing;
    eval { $existing = Devel::Cover::DB->new(db => $DB) if $Merge };
    $cover->merge($existing) if $existing;
    $cover->indent($Indent);
    $cover->write($DB);
    $cover->print_summary if $Summary;
}

sub add_statement_cover
{
    my ($op) = @_;

    get_location($op);
    return unless $F;

    return unless $Devel::Cover::collect;

    # print "Statement: ", $op->name, "\n";

    my $key = pack("I*", $$op) . pack("I*", $op->seq);
    push @{$Cover->{$F}{statement}{$L}}, [[$Coverage->{statement}{$key} || 0]];
    push @{$Cover->{$F}{time}{$L}},      [[$Coverage->{time}{$key}]]
        if exists $Coverage->{time} && exists $Coverage->{time}{$key};
}

sub add_condition_cover
{
    return unless $Devel::Cover::collect;

    my ($op, $strop, $left, $right) = @_;

    my $key = pack("I*", $$op) . pack("I*", $op->seq);
    # print STDERR "Condition cover from $F:$L\n";

    $Coverage->{condition}{$key} = [0, 0, 0]
        unless @{$Coverage->{condition}{$key}};
    push @{$Cover->{$F}{condition}{$L}},
         [
             [ map($_ || 0, @{$Coverage->{condition}{$key}}) ],
             {
                 type  => $op->name,
                 op    => $strop,
                 left  => $left,
                 right => $right,
             },
         ];
}

sub add_branch_cover
{
    return unless $Devel::Cover::collect;

    my ($op, $type, $text) = @_;

    $text =~ s/^\s+//;
    $text =~ s/\s+$//;

    my $key = pack("I*", $$op) . pack("I*", $op->seq);
    # print STDERR "Branch cover from $F:$L\n";

    my $c;
    if ($type eq "and")
    {
        $c = $Coverage->{condition}{$key};
        $c = [ ($c->[0] || 0), ($c->[1] || 0) + ($c->[2] || 0) ];
    }
    elsif ($type eq "or")
    {
        $c = $Coverage->{condition}{$key};
        $c = [ ($c->[0] || 0) + ($c->[1] || 0), ($c->[2] || 0) ];
    }
    else
    {
        $c = $Coverage->{branch}{$key} || [0, 0];
    }

    push @{$Cover->{$F}{branch}{$L}},
         [
             [ map($_ || 0, @$c) ],
             {
                 text  => $text,
             },
         ];
}

sub is_scope       { &B::Deparse::is_scope }
sub is_state       { &B::Deparse::is_state }
sub is_ifelse_cont { &B::Deparse::is_ifelse_cont }

{

no warnings "redefine";

$Devel::Cover::collect = 1;

sub B::Deparse::deparse
{
    my $self = shift;
    my ($op, $cx) = @_;

    my $class = class($op);
    my $null  = $class eq "NULL";

    my $name = $op->can("name") ? $op->name : "Unknown";

    # print "Deparse <$name>\n";

    if ($Devel::Cover::collect)
    {
        # Get the coverage on this op.

        if ($class eq "COP" && $Coverage{statement})
        {
            add_statement_cover($op);
        }
        elsif (!$null && $name eq "null"
                      && ppname($op->targ) eq "pp_nextstate"
                      && $Coverage{statement})
        {
            # If the current op is null, but it was nextstate, we can still
            # get at the file and line number, but we need to get dirty.

            my $o = $op;
            bless $o, "B::COP";
            add_statement_cover($o);
        }
        elsif ($name eq "cond_expr")
        {
            my $cond  = $op->first;
            my $true  = $cond->sibling;
            my $false = $true->sibling;
            if (!($cx == 0 && (is_scope($true) && $true->name ne "null") &&
                    (is_scope($false) || is_ifelse_cont($false))
                    && $self->{'expand'} < 7))
            {
                {
                    local $Devel::Cover::collect = 0;
                    $cond = $self->deparse($cond, 8);
                }
                add_branch_cover($op, "if", "$cond ? :");
            }
            else
            {
                {
                    local $Devel::Cover::collect = 0;
                    $cond = $self->deparse($cond, 1);
                }
                add_branch_cover($op, "if", "if ($cond) { }");
                while (class($false) ne "NULL" && is_ifelse_cont($false))
                {
                    my $newop   = $false->first;
                    my $newcond = $newop->first;
                    my $newtrue = $newcond->sibling;
                    # last in chain is OP_AND => no else
                    $false = $newtrue->sibling;
                    {
                        local $Devel::Cover::collect = 0;
                        $newcond = $self->deparse($newcond, 1);
                    }
                    add_branch_cover($newop, "elsif", "elsif ($newcond) { }");
                }
            }
        }
    }

    # Wander down the tree.

    my $meth = "pp_$name";
    $self->$meth($op, $cx)
}

sub B::Deparse::logop
{
    my $self = shift;
    my ($op, $cx, $lowop, $lowprec, $highop, $highprec, $blockname) = @_;
    my $left  = $op->first;
    my $right = $op->first->sibling;
    if ($cx == 0 && is_scope($right) && $blockname && $self->{expand} < 7)
    {
        # if ($a) {$b}
        $left  = $self->deparse($left, 1);
        $right = $self->deparse($right, 0);
        add_branch_cover($op, $lowop, "$blockname ($left)");
        return "$blockname ($left) {\n\t$right\n\b}\cK"
    }
    elsif ($cx == 0 && $blockname && !$self->{parens} && $self->{expand} < 7)
    {
        # $b if $a
        $right = $self->deparse($right, 1);
        $left  = $self->deparse($left, 1);
        add_branch_cover($op, $lowop, "$blockname $left");
        return "$right $blockname $left"
    }
    elsif ($cx > $lowprec && $highop)
    {
        # $a && $b
        $left  = $self->deparse_binop_left($op, $left, $highprec);
        $right = $self->deparse_binop_right($op, $right, $highprec);
        add_condition_cover($op, $highop, $left, $right);
        return $self->maybe_parens("$left $highop $right", $cx, $highprec)
    }
    else
    {
        # $a and $b
        $left  = $self->deparse_binop_left($op, $left, $lowprec);
        $right = $self->deparse_binop_right($op, $right, $lowprec);
        add_condition_cover($op, $lowop, $left, $right);
        return $self->maybe_parens("$left $lowop $right", $cx, $lowprec)
    }
}

}

sub get_cover
{
    my $deparse = B::Deparse->new;

    my $cv = $deparse->{curcv} = shift;

    @_ ? $deparse->deparse(shift, 0) : $deparse->deparse_sub($cv, 0)
}

bootstrap Devel::Cover $VERSION;

1

__END__

=head1 NAME

Devel::Cover - Code coverage metrics for Perl

=head1 SYNOPSIS

 perl -MDevel::Cover yourprog args
 cover cover_db -report html

 perl -MDevel::Cover=-db,cover_db,-coverage,statement,time yourprog args

=head1 DESCRIPTION

This module provides code coverage metrics for Perl.

If you can't guess by the version number this is an alpha release.

Code coverage data are collected using a plugable runops function which
counts how many times each op is executed.  These data are then mapped
back to reality using the B compiler modules.  There is also a statement
profiling facility which needs a better backend to be really useful.

The B<cover> program can be used to generate coverage reports.

Statement, branch, condition, pod and time coverage information is
reported.  Statement coverage data should be reasonable, although there
may be some statements which are not reported.  Branch coverage data
should be mostly accurate too.  Condition coverage data are only
available for && and || ops.  These data should be mostly accurate,
although not always what one might initially expect.  Pod coverage comes
from Pod::Coverage.  Coverage data for path coverage are not yet
collected.

The B<gcov2perl> program can be used to convert gcov files to
Devel::Cover databases.

You may find that the results don't match your expectations.  I would
imagine that at least one of them is wrong.

THe most appropriate mailing list on which to discuss this module would
be perl-qa.  Discussion has migrated there from perl-qa-metrics which is
now defunct.  http://lists.perl.org/showlist.cgi?name=perl-qa

Requirements:

  Perl 5.6.1 or 5.7.1.
  The ability to compile XS extensions.
  Pod::Coverage if you want pod coverage.
  Template Toolkit 2 if you want HTML output.

=head1 OPTIONS

 -coverage criterion - Turn on coverage for the specified criterion.
 -db cover_db        - Store results in coverage db (default cover_db).
 -inc path           - Set prefixes of files to ignore (default @INC).
 +inc path           - Append to prefixes of files to ignore.
 -ignore RE          - Ignore files matching RE.
 -indent indent      - Set indentation level to indent.  Don't use this.
 -merge val          - Merge databases, for multiple test benches (default on).
 -profile val        - Turn on profiling iff val is true (default on).
 -select RE          - Only report on files matching RE.
 -summary val        - Print summary information iff val is true (default on).

=head1 ACKNOWLEDGEMENTS

Some code and ideas cribbed from:

 Devel::OpProf
 B::Concise
 B::Deparse

=head1 SEE ALSO

 Devel::Cover::Tutorial
 Data::Dumper
 B
 Pod::Coverage

=head1 BUGS

Did I mention that this is alpha code?

=head1 VERSION

Version 0.15 - 5th September 2002

=head1 LICENCE

Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

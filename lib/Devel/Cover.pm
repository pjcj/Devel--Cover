# Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover;

use strict;
use warnings;

our @ISA     = qw( DynaLoader );
our $VERSION = "0.18";

use DynaLoader ();

use Devel::Cover::DB  0.18;
use Devel::Cover::Inc 0.18;

use B qw( class ppname main_cv main_start main_root walksymtable OPf_KIDS );
use B::Debug;
use B::Deparse;

use Cwd ();

BEGIN { eval "use Pod::Coverage 0.06" }     # We'll use this if it is available.

my $Silent  = 0;                            # Output nothing.

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

use vars qw($File $Line $Collect);

($File, $Line, $Collect) = ("", 0, 1);

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
          "Ignoring packages in:",        join("\n    ", "", @Inc),    "\n"
        unless $Silent;
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
        /^-silent/   && do { $Silent     = shift; next };
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

sub get_location
{
    my ($op) = @_;

    $File = $op->file;
    $Line = $op->line;

    # If there's an eval, get the real filename.  Enabled from $^P & 0x100.

    ($File, $Line) = ($1, $2) if $File =~ /^\(eval \d+\)\[(.*):(\d+)\]/;

    $File =~ s/ \(autosplit into .*\)$//;
    $File =~ s/^$Cwd\///;

    # print "File: $File\n";
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
        unless $Silent || ($files->{$file} || $file =~ /\(eval \d+\)/);
    $files->{$file}
}

sub check_file
{
    my ($cv) = @_;

    return unless class($cv) eq "CV";

    my $op = $cv->START;
    return unless $op->can("file") && class($op) ne "NULL" && is_state($op);

    my $file = $op->file;
    my $use  = use_file($file);
    # printf "%6s $file\n", $use ? "use" : "ignore";

    $use
}

sub B::GV::find_cv
{
    my $cv = $_[0]->CV;
    return unless $$cv;

    push @Cvs, $cv if check_file($cv);
    push @Cvs, grep check_file($_), $cv->PADLIST->ARRAY->ARRAY
        if $cv->PADLIST->can("ARRAY") &&
           $cv->PADLIST->ARRAY &&
           $cv->PADLIST->ARRAY->can("ARRAY");
};

sub check_files
{
    # print "Checking files\n";

    @Cvs = grep check_file($_), B::main_cv->PADLIST->ARRAY->ARRAY;

    my %seen_pkg;

    walksymtable(\%main::, "find_cv", sub { !$seen_pkg{$_[0]}++ });

    # use Data::Dumper;
    # print Dumper \%seen_pkg;
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

    check_files();

    get_cover(main_cv, main_root);
    get_cover($_) for @Cvs;

    for my $file (keys %$Cover)
    {
        delete $Cover->{$file} unless use_file($file);
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
    $cover->print_summary if $Summary && !$Silent;
}

sub add_statement_cover
{
    my ($op) = @_;

    get_location($op);
    return unless $File;

    return unless $Collect;

    # print "Statement: ", $op->name, "\n";

    my $key = pack("I*", $$op) . pack("I*", $op->seq);
    push @{$Cover->{$File}{statement}{$Line}},
         [[$Coverage->{statement}{$key} || 0]];
    push @{$Cover->{$File}{time}{$Line}},
         [[$Coverage->{time}{$key}]]
        if exists $Coverage->{time} && exists $Coverage->{time}{$key};
}

sub add_branch_cover
{
    return unless $Collect;

    my ($op, $type, $text, $file, $line) = @_;

    $text =~ s/^\s+//;
    $text =~ s/\s+$//;

    my $key = pack("I*", $$op) . pack("I*", $op->seq);
    # print STDERR "Branch cover from $file:$line\n";

    my $c = $Coverage->{condition}{$key};
    if ($type eq "and")
    {
        shift @$c;
        $c = [ ($c->[2] || 0), ($c->[0] || 0) + ($c->[1] || 0) ];
    }
    elsif ($type eq "or")
    {
        shift @$c;
        $c = [ ($c->[2] || 0) + ($c->[0] || 0), ($c->[1] || 0) ];
    }
    else
    {
        $c = $Coverage->{branch}{$key} || [0, 0];
    }

    push @{$Cover->{$file}{branch}{$line}},
         [
             [ map($_ || 0, @$c) ],
             {
                 text  => $text,
             },
         ];
}

sub add_condition_cover
{
    return unless $Collect;

    my ($op, $strop, $left, $right) = @_;

    my $key = pack("I*", $$op) . pack("I*", $op->seq);
    # print STDERR "Condition cover from $File:$Line\n";

    my $type = $op->name;
    $type =~ s/assign$//;

    my $c = $Coverage->{condition}{$key};
    shift @$c;

    my $count;

    if ($type eq "or")
    {
        if ($op->first->sibling->name eq "const")
        {
            $c = [ ($c->[2] || 0), ($c->[0] || 0) + ($c->[1] || 0) ];
            $count = 2;
        }
        else
        {
            @$c = @{$c}[2, 1, 0];
            $count = 3;
        }
    }
    elsif ($type eq "and")
    {
        @$c = @{$c}[2, 0, 1];
        $count = 3;
    }
    elsif ($type eq "xor")
    {
        # !l&&!r  l&&!r  l&&r  !l&&r
        @$c = @{$c}[2, 1, 3, 0];
        $count = 4;
    }
    else
    {
        die qq(Unknown type "$type" for conditional);
    }

    push @{$Cover->{$File}{condition}{$Line}},
         [
             $c,
             {
                 type  => "${type}_${count}",
                 op    => $strop,
                 left  => $left,
                 right => $right,
             },
         ];
}

sub is_scope       { &B::Deparse::is_scope }
sub is_state       { &B::Deparse::is_state }
sub is_ifelse_cont { &B::Deparse::is_ifelse_cont }

{

no warnings "redefine";

my $original_deparse;
BEGIN { $original_deparse = \&B::Deparse::deparse }

sub B::Deparse::deparse
{
    my $self = shift;
    my ($op, $cx) = @_;

    my $class = class($op);
    my $null  = $class eq "NULL";

    my $name = $op->can("name") ? $op->name : "Unknown";

    # print "Deparse <$name>\n";

    if ($Collect)
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

            bless $op, "B::COP";
            add_statement_cover($op);
            bless $op, "B::$class";
        }
        elsif ($name eq "cond_expr")
        {
            local ($File, $Line) = ($File, $Line);
            my $cond  = $op->first;
            my $true  = $cond->sibling;
            my $false = $true->sibling;
            if (!($cx == 0 && (is_scope($true) && $true->name ne "null") &&
                    (is_scope($false) || is_ifelse_cont($false))
                    && $self->{'expand'} < 7))
            {
                my ($file, $line) = ($File, $Line);
                { local $Collect; $cond = $self->deparse($cond, 8) }
                add_branch_cover($op, "if", "$cond ? :", $file, $line);
            }
            else
            {
                my ($file, $line) = ($File, $Line);
                { local $Collect; $cond = $self->deparse($cond, 1) }
                add_branch_cover($op, "if", "if ($cond) { }", $file, $line);
                while (class($false) ne "NULL" && is_ifelse_cont($false))
                {
                    my $newop   = $false->first;
                    my $newcond = $newop->first;
                    my $newtrue = $newcond->sibling;
                    # last in chain is OP_AND => no else
                    $false = $newtrue->sibling;
                    my ($file, $line) = ($File, $Line);
                    { local $Collect; $newcond = $self->deparse($newcond, 1) }
                    add_branch_cover($newop, "elsif", "elsif ($newcond) { }",
                                     $file, $line);
                }
            }
        }
    }

    $original_deparse->($self, @_);
}

sub B::Deparse::logop
{
    my $self = shift;
    my ($op, $cx, $lowop, $lowprec, $highop, $highprec, $blockname) = @_;
    my $left  = $op->first;
    my $right = $op->first->sibling;
    my ($file, $line) = ($File, $Line);
    if ($cx == 0 && is_scope($right) && $blockname && $self->{expand} < 7)
    {
        # if ($a) {$b}
        $left  = $self->deparse($left, 1);
        $right = $self->deparse($right, 0);
        add_branch_cover($op, $lowop, "$blockname ($left)", $file, $line);
        return "$blockname ($left) {\n\t$right\n\b}\cK"
    }
    elsif ($cx == 0 && $blockname && !$self->{parens} && $self->{expand} < 7)
    {
        # $b if $a
        $right = $self->deparse($right, 1);
        $left  = $self->deparse($left, 1);
        add_branch_cover($op, $lowop, "$blockname $left", $file, $line);
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

sub B::Deparse::logassignop {
    my $self = shift;
    my ($op, $cx, $opname) = @_;
    my $left = $op->first;
    my $right = $op->first->sibling->first; # skip sassign
    $left = $self->deparse($left, 7);
    $right = $self->deparse($right, 7);
    add_condition_cover($op, $opname, $left, $right);
    return $self->maybe_parens("$left $opname $right", $cx, 7);
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
may be some statements which are not reported.  Branch and condition
coverage data should be mostly accurate too.  These data should be
mostly accurate, although not always what one might initially expect.
Pod coverage comes from Pod::Coverage.  Coverage data for path coverage
are not yet collected.

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

Version 0.18 - 28th September 2002

=head1 LICENCE

Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

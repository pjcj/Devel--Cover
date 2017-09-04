package Devel::Cover::Report::Html_subtle;
use strict;
use warnings;

# VERSION

use Devel::Cover::DB;
use Devel::Cover::Html_Common "launch";
use Devel::Cover::Truth_Table;

use Getopt::Long;
use Template 2.00;
use HTML::Entities;

my $Template;
my %Filenames;
my %File_exists;

sub get_options {
    my ($self, $opt) = @_;
    $opt->{option}{outputfile} = "coverage.html";
    die "Invalid command line options" unless
        GetOptions($opt->{option},
                   qw(
                       outputfile=s
                     ));
}

#-------------------------------------------------------------------------------
# Subroutine : cvg_class()
# Purpose    : Determine the CSS class for an element based on its amount of
#              coverage.
# Notes      :
#-------------------------------------------------------------------------------
sub cvg_class {
    my ($pc, $err) = @_;
    defined $err && !$err ? "covered"
                          : $pc <  75 ? "uncovered"
                          : $pc <  90 ? "covered75"
                          : $pc < 100 ? "covered90"
                          : "covered";
}


#-------------------------------------------------------------------------------
# Subroutine : print_stylesheet()
# Purpose    : Create the stylesheet for HTML reports.
# Notes      :
#-------------------------------------------------------------------------------
sub print_stylesheet {
    my $db = shift;
    my $file = "$db->{db}/cover.css";
    open(CSS, '>', $file) or return;
    my $p = tell(DATA);
    print CSS <DATA>;
    seek(DATA, $p, 0);
    close(CSS);
}

#-------------------------------------------------------------------------------
# Subroutine : print_summary()
# Purpose    : Print the database summary report.
# Notes      :
#-------------------------------------------------------------------------------
sub print_summary {
    my ($db, $options) = @_;
    my @showing = grep $options->{show}{$_}, $db->all_criteria;
    my @headers = map { ($db->all_criteria_short)[$_] }
    grep { $options->{show}{($db->all_criteria)[$_]} }
    (0 .. $db->all_criteria - 1);
    my @files = (grep($db->{summary}{$_}, @{$options->{file}}), 'Total');

    my %vals;
    for my $file (@files) {
        my %pvals;
        my $part = $db->{summary}{$file};
        for my $criterion (@showing) {
            my $pc = exists $part->{$criterion}
                ? do { my $x = sprintf "%5.2f", $part->{$criterion}{percentage};
                       chop $x; $x }
                : "n/a";

            if ($pc ne 'n/a') {
                if ($criterion ne 'time') {
                    $vals{$file}{$criterion}{class} = cvg_class($pc);
                }
                if (exists $Filenames{$file}) {
                    if ($criterion eq 'branch') {
                        $vals{$file}{$criterion}{link} = "$Filenames{$file}--branch.html";
                    } elsif ($criterion eq 'condition') {
                        $vals{$file}{$criterion}{link} = "$Filenames{$file}--condition.html";
                    } elsif ($criterion eq 'subroutine') {
                        $vals{$file}{$criterion}{link} = "$Filenames{$file}--subroutine.html";
                    }
                }
                my $c = $part->{$criterion};
                $vals{$file}{$criterion}{details} =
                ($c->{covered} || 0) . " / " . ($c->{total} || 0);
            }
            $vals{$file}{$criterion}{pc} = $pc;
        }
    }

    my $vars = {
        title       => "Coverage Summary: $db->{db}",
        dbname      => $db->{db},
        showing     => \@showing,
        headers     => \@headers,
        files       => \@files,
        filenames   => \%Filenames,
        file_exists => \%File_exists,
        vals        => \%vals,
    };

    my $html = "$options->{outputdir}/$options->{option}{outputfile}";
    $Template->process("summary", $vars, $html) or die $Template->error();

    print "HTML output written to $html\n" unless $options->{silent};
}


#-------------------------------------------------------------------------------
# Subroutine : get_metrics()
# Purpose    : Determine which metrics to include in report.
# Notes      :
#-------------------------------------------------------------------------------
sub get_metrics {
    my ($db, $options, $file_data, $line) = @_;
    my %m;

    for my $c ($db->criteria) {                   # find all metrics available in db
        next unless $options->{show}{$c};         # skip those we don't want in report
        my $criterion = $file_data->$c();         # check if metric collected for this file
        if ($criterion) {                         # if it exists...
            my $li = $criterion->location($line); #   get the metric info for the current line
            $m{$c} = $li ? [@$li] : undef;        #   and stash it
        }
    }
    return %m;
}


#-------------------------------------------------------------------------------
# Subroutine : print_file()
# Purpose    : Print coverage overview report for a file.
# Notes      :
#-------------------------------------------------------------------------------
sub print_file {
    my ($db, $file, $options) = @_;

    open(F,'<',  $file) or warn("Unable to open '$file' [$!]\n"), return;

    my @lines;
    my @showing = grep $options->{show}{$_}, $db->criteria;
    my @headers = map { ($db->all_criteria_short)[$_] }
    grep { $options->{show}{($db->criteria)[$_]} } (0 .. $db->criteria - 1);

    my $file_data = $db->cover->file($file);

    while (my $l = <F>) {
        chomp $l;

        my %metric = get_metrics($db, $options, $file_data, $.);
        my %line = (
            number  => $.,
            text    => encode_entities($l),
            metrics => [],
        );
        $line{text} =~ s/\t/        /g;
        $line{text} =~ s/\s/&nbsp;/g; # IE doesn't honor "white-space: pre" CSS

        foreach my $c ($db->criteria) {
            next unless $options->{show}{$c};
            push(@{$line{metrics}}, []), next unless $metric{$c};

            if ($c eq 'branch') {
                my @p;
                foreach (@{$file_data->branch->get($.)}) {
                    push @p, {text  => sprintf("%.0f", $_->percentage),
                    class => cvg_class($_->percentage),
                    link  => "$Filenames{$file}--branch.html#line$."};
                }
                push @{$line{metrics}}, \@p;
            } elsif ($c eq 'condition') {
                my @tt = $file_data->condition->truth_table($.);
                my @p;
                if (@tt) {
                    foreach (@tt) {
                        push @p, {text  => sprintf("%.0f", $_->[0]->percentage),
                        class => cvg_class($_->[0]->percentage),
                        link  => "$Filenames{$file}--condition.html#line$."};
                    }
                } else {
                    push @p, { text => "expression contains > 16 terms: ignored" };
                }
                push @{$line{metrics}}, \@p;
            } elsif ($c eq 'subroutine') {
                my @p;
                while (my $o = shift @{$metric{$c}}) {
                    push @p, {text  => $o->covered,
                    class => $o->error ? 'uncovered' : 'covered',
                    link  => "$Filenames{$file}--subroutine.html#line$."};
                }
                push @{$line{metrics}}, \@p;
            } else {
                my @p;
                while (my $o = shift @{$metric{$c}}) {
                    push @p, {text  => ($c =~ /statement|pod|time/) ? $o->covered : $o->percentage,
                    class => $c eq 'time' ? undef : $o->error ? 'uncovered' : 'covered',
                    link  => undef};
                }
                push @{$line{metrics}}, \@p;
            }
        }
        push @lines, \%line;
        last if $l =~ /^__(END|DATA)__/;
    }
    close F or die "Unable to close '$file' [$!]";

    my $vars = {
        title       => "File Coverage: $file",
        file        => $file,
        percentage  => sprintf("%.1f", $db->{summary}{$file}{total}{percentage}),
        class       => cvg_class($db->{summary}{$file}{total}{percentage}),
        showing     => \@showing,
        headers     => \@headers,
        filenames   => \%Filenames,
        file_exists => \%File_exists,
        lines       => \@lines,
        perlver     => join('.', map {ord} split(//, $^V)), # should come from db
        platform    => $^O,                                 # should come from db
    };

    my $html = "$options->{outputdir}/$Filenames{$file}.html";
    $Template->process("file", $vars, $html) or die $Template->error();
}


#-------------------------------------------------------------------------------
# Subroutine : print_branches()
# Purpose    : Print branch coverage report for a file.
# Notes      :
#-------------------------------------------------------------------------------
sub print_branches {
    my ($db, $file, $options) = @_;

    my $branches = $db->cover->file($file)->branch;

    return unless $branches;

    my @branches;
    for my $location (sort { $a <=> $b } $branches->items) {
        my $count = 0;
        for my $b (@{$branches->location($location)}) {
            my @tf = $b->values;
            push @branches,
            {
                ref        => "line$location",
                number     => $count++ ? undef : $location,
                percentage => sprintf("%.0f", $b->percentage),
                class      => cvg_class($b->percentage),
                parts      => [{text => 'T', class => $tf[0] ? 'covered' : 'uncovered'},
                {text => 'F', class => $tf[1] ? 'covered' : 'uncovered'}],
                text       => encode_entities($b->text),
            };
        }
    }

    my $vars = {
        title       => "Branch Coverage: $file",
        file        => $file,
        percentage  => sprintf("%.1f", $db->{summary}{$file}{branch}{percentage}),
        class       => cvg_class($db->{summary}{$file}{branch}{percentage}),
        branches    => \@branches,
        perlver     => join('.', map {ord} split(//, $^V)), # should come from db
        platform    => $^O,                                 # should come from db
    };

    my $html = "$options->{outputdir}/$Filenames{$file}--branch.html";
    $Template->process("branches", $vars, $html) or die $Template->error();
}


#-------------------------------------------------------------------------------
# Subroutine : print_conditions()
# Purpose    : Print condition coverage report for a file.
# Notes      :
#-------------------------------------------------------------------------------
sub print_conditions {
    my ($db, $file, $options) = @_;
    my $conditions = $db->cover->file($file)->condition;
    return unless $conditions;

    my @data;
    for my $location (sort { $a <=> $b } $conditions->items) {
        my @x = $conditions->truth_table($location);

        for my $c (@x) {
            push @data, {
                line       => $location,
                ref        => "line$location",
                percentage => sprintf("%.0f", $c->[0]->percentage),
                class      => cvg_class($c->[0]->percentage),
                condition  => encode_entities($c->[1]),
                coverage   => $c->[0]->html,
            };
        }
    }

    my $vars = {
        title      => "Condition Coverage: $file",
        file        => $file,
        percentage  => sprintf("%.1f", $db->{summary}{$file}{condition}{percentage}),
        class       => cvg_class($db->{summary}{$file}{condition}{percentage}),
        headers     => ['line', '%', 'coverage', 'condition'],
        conditions  => \@data,
        perlver     => join('.', map {ord} split(//, $^V)), # should come from db
        platform    => $^O,                                 # should come from db
    };

    my $html = "$db->{db}/$Filenames{$file}--condition.html";
    $Template->process("conditions", $vars, $html)
        or die $Template->error();
}

sub print_subroutines {
    my ($db, $file, $options) = @_;
    my $subroutines = $db->cover->file($file)->subroutine;
    return unless $subroutines;

    my @data;
    for my $location ($subroutines->items) {
        my $l = $subroutines->location($location);
        for my $sub (@$l) {
            push @data, {
                ref   => "line$location",
                line  => $location,
                name  => $sub->name,
                class => cvg_class($sub->percentage),
            }
        }
    }

    my $vars = {
        title      => "Subroutine Coverage: $file",
        file        => $file,
        percentage  => sprintf("%.1f", $db->{summary}{$file}{subroutine}{percentage}),
        class       => cvg_class($db->{summary}{$file}{subroutine}{percentage}),
        subroutines =>  [ sort { $a->{name} cmp $b->{name} } @data ],
        perlver     => join('.', map {ord} split(//, $^V)), # should come from db
        platform    => $^O,                                 # should come from db
    };

    my $html = "$db->{db}/$Filenames{$file}--subroutine.html";
    $Template->process("subroutines", $vars, $html)
        or die $Template->error();
}


#-------------------------------------------------------------------------------
# Subroutine : report()
# Purpose    : Entry point for printing HTML reports.
# Notes      :
#-------------------------------------------------------------------------------
sub report {
    my ($pkg, $db, $options) = @_;

    $Template = Template->new({
        LOAD_TEMPLATES => [Devel::Cover::Report::Html_subtle::Template::Provider->new({}),],
    });

    %Filenames   = map {$_ => do {(my $f = $_) =~ s/\W/-/g; $f}} @{$options->{file}};
    %File_exists = map {$_ => -e} @{$options->{file}};

    print_stylesheet($db);

    for my $file (@{$options->{file}}) {
        print_file($db,        $file, $options);
        print_branches($db,    $file, $options) if $options->{show}{branch};
        print_conditions($db,  $file, $options) if $options->{show}{condition};
        print_subroutines($db, $file, $options) if $options->{show}{subroutine};
    }
    print_summary($db, $options);
}

1;

package Devel::Cover::Report::Html_subtle::Template::Provider;
use strict;
use warnings;

# VERSION

use base "Template::Provider";

my %Templates;

sub fetch {
    my $self = shift;
    my ($name) = @_;

    # print "Looking for <$name>\n";
    $self->SUPER::fetch(exists $Templates{$name} ? \$Templates{$name} : $name);
}

#<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
$Templates{html} = <<'EOT';
<?xml version="1.0" encoding="utf-8"?>
<!--
This file was generated by Devel::Cover Version $VERSION
Devel::Cover is copyright 2001-2017, Paul Johnson (paul\@pjcj.net)
Devel::Cover is free. It is licensed under the same terms as Perl itself.
The latest version of Devel::Cover should be available from my homepage:
http://www.pjcj.net
-->
<!DOCTYPE html
    PUBLIC "-//W3C//DTD XHTML Basic 1.0//EN"
    "http://www.w3.org/TR/xhtml-basic/xhtml-basic10.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1"></meta>
    <meta http-equiv="Content-Language" content="en-us"></meta>
    <link rel="stylesheet" type="text/css" href="cover.css"></link>
    <title> [% title %] </title>
</head>
<body>
    [% content %]
</body>
</html>
EOT

$Templates{summary} = <<'EOT';
[% WRAPPER html %]

<h1>Coverage Summary</h1>
<table>
    <tr>
        <td class="header" align="right">Database:</td>
        <td>[% dbname %]</td>
    </tr>
</table>
<div><br></br></div>
<table>

    <tr>
    <th align="left" class="header"> File </th>
    [% FOREACH header = headers %]
        <th class="header"> [% header %] </th>
    [% END %]
    </tr>

    [% FOREACH file = files %]
        <tr align="center" valign="top">
        <td align="left">
        [% IF file_exists.$file %]
           <a href="[%- filenames.$file -%].html"> [% file %] </a>
        [% ELSE %]
            [% file %]
        [% END %]
        </td>

        [% FOREACH criterion = showing %]
            [% IF vals.$file.$criterion.class %]
                <td class="[%- vals.$file.$criterion.class -%]"
                    title="[%- vals.$file.$criterion.details -%]">
            [% ELSE %]
                <td>
            [% END %]
            [% IF vals.$file.$criterion.link.defined%]
                <a href="[% vals.$file.$criterion.link %]">
                [% vals.$file.$criterion.pc %]
                </a>
            [% ELSE %]
                [% vals.$file.$criterion.pc %]
            [% END %]
            </td>
        [% END %]
        </tr>
    [% END %]

</table>

[% END %]
EOT

$Templates{branches} = <<'EOT';
[% WRAPPER html %]

<h1>Branch Coverage</h1>
<table>
    <tr>
        <td class="header" align="right">File:</td>
        <td>[% file %]</td>
    </tr>
    <tr>
        <td class="header" align="right">Coverage:</td>
        <td class="[% class %]">[% percentage %]%</td>
    </tr>
    <tr>
        <td class="header" align="right">Perl version:</td>
        <td>[% perlver %]</td>
    </tr>
    <tr>
        <td class="header" align="right">Platform:</td>
        <td>[% platform %]</td>
    </tr>
</table>
<div><br></br></div>
<table>
    <tr valign="top">
        <th class="header"> line </th>
        <th class="header"> % </th>
        <th colspan="2" class="header"> coverage </th>
        <th class="header"> branch </th>
    </tr>

    [% FOREACH branch = branches %]
        <tr align="center" valign="top">
            <td class="header">
            [% IF branch.number.defined %]
                <a id="[% branch.ref %]">[% branch.number %]</a>
            [% ELSE %]
                [% branch.number %]
            [% END %]
            </td>
            <td class="[% branch.class %]"> [% branch.percentage %] </td>
            [% FOREACH part = branch.parts %]
                <td class="[% part.class %]"> [% part.text %] </td>
            [% END %]
            <td align="left">
                <code>[% branch.text %]</code>
            </td>
        </tr>
    [% END %]

</table>

[% END %]
EOT

$Templates{conditions} = <<'EOT';
[% WRAPPER html %]

<h1>Condition Coverage</h1>
<table>
    <tr>
        <td class="header" align="right">File:</td>
        <td>[% file %]</td>
    </tr>
    <tr>
        <td class="header" align="right">Coverage:</td>
        <td class="[% class %]">[% percentage %]%</td>
    </tr>
    <tr>
        <td class="header" align="right">Perl version:</td>
        <td>[% perlver %]</td>
    </tr>
    <tr>
        <td class="header" align="right">Platform:</td>
        <td>[% platform %]</td>
    </tr>
</table>
<div><br></br></div>
<table>
    <tr>
        [% FOREACH header = headers %]
            <th class="header"> [% header %] </th>
        [% END %]
    </tr>

    [% FOREACH cond = conditions %]
        <tr valign="top">
            <td align="center" class="header"><a id="[% cond.ref %]">
                [% cond.line %]
            </a></td>
            <td align="center" class="[% cond.class %]">
                [% cond.percentage %]
            </td>
            <td><div>
                [% cond.coverage %]
            </div></td>
            <td>
                <code>[% cond.condition %]</code>
            </td>
        </tr>
    [% END %]

</table>

[% END %]
EOT

$Templates{subroutines} = <<'EOT';
[% WRAPPER html %]

<h1>Subroutine Coverage</h1>
<table>
    <tr>
        <td class="header" align="right">File:</td>
        <td>[% file %]</td>
    </tr>
    <tr>
        <td class="header" align="right">Coverage:</td>
        <td class="[% class %]">[% percentage %]%</td>
    </tr>
    <tr>
        <td class="header" align="right">Perl version:</td>
        <td>[% perlver %]</td>
    </tr>
    <tr>
        <td class="header" align="right">Platform:</td>
        <td>[% platform %]</td>
    </tr>
</table>
<div><br></br></div>
<table>
    <tr valign="top">
        <th class="header"> subroutine </th>
        <th class="header"> line </th>
    </tr>

    [% FOREACH sub = subroutines %]
        <tr align="center" valign="top">
            <td class="[% sub.class %]"> <a id="[% sub.ref %]"> [% sub.name %] </td>
            <td> [% sub.line %] </td>
        </tr>
    [% END %]

</table>

[% END %]
EOT

$Templates{file} = <<'EOT';
[% WRAPPER html %]

<h1>File Coverage</h1>
<table>
    <tr>
        <td class="header" align="right">File:</td>
        <td>[% file %]</td>
    </tr>
    <tr>
        <td class="header" align="right">Coverage:</td>
        <td class="[% class %]">[% percentage %]%</td>
    </tr>
    <tr>
        <td class="header" align="right">Perl version:</td>
        <td>[% perlver %]</td>
    </tr>
    <tr>
        <td class="header" align="right">Platform:</td>
        <td>[% platform %]</td>
    </tr>
</table>
<div><br></br></div>
<table>

    <tr>
        <th class="header">line</th>
        [% FOREACH header = headers %]
            <th class="header">[% header %]</th>
        [% END %]
        <th class="header">code</th>
    </tr>

    [% FOREACH line = lines %]
        <tr align="center" valign="top">
            <td class="header">[% line.number %]</td>
            [% FOREACH metric = line.metrics %]
                <td>
                [% FOREACH cr = metric %]
                    [% IF cr.class.defined %]
                        <div class="[% cr.class %]">
                    [% ELSE %]
                        <div>
                    [% END %]
                    [% IF cr.link.defined %]
                        <a href="[% cr.link %]">[% cr.text %]</a>
                    [% ELSE %]
                        [% cr.text %]
                    [% END %]
                    </div>
                [% END %]
                </td>
            [% END %]
            <td align="left">
                <code>[% line.text %]</code>
            </td>
        </tr>
    [% END %]

</table>

[% END %]
EOT

# remove some whitespace from templates
s/^\s+//gm for values %Templates;

1;

=pod

=head1 NAME

Devel::Cover::Report::Html_subtle - HTML backend for Devel::Cover

=head1 SYNOPSIS

 cover -report html_subtle

=head1 DESCRIPTION

This module provides a HTML reporting mechanism for coverage data.  It
is designed to be called from the C<cover> program.

Based on an original by Paul Johnson, the output was greatly improved by
Michael Carman (mjcarman@mchsi.com).

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2001-2017, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

package Devel::Cover::Report::Html_subtle;

__DATA__
/* Stylesheet for Devel::Cover HTML reports */

/* You may modify this file to alter the appearance of your coverage
 * reports. If you do, you should probably flag it read-only to prevent
 * future runs from overwriting it.
 */

/* Note: default values use the color-safe web palette. */

body {
    font-family: sans-serif;
}

h1 {
    background-color: #3399ff;
    border: solid 1px #999999;
    padding: 0.2em;
}

a {
    color: #000000;
}
a:visited {
    color: #333333;
}

code {
    white-space: pre;
}

table {
/*    border: solid 1px #000000;*/
    border-collapse: collapse;
    border-spacing: 0px;
}
td,th {
    border: solid 1px #cccccc;
}

/* Classes for color-coding coverage information:
 *   header    : column/row header
 *   uncovered : path not covered or coverage < 75%
 *   covered75 : coverage >= 75%
 *   covered90 : coverage >= 90%
 *   covered   : path covered or coverage = 100%
 */
.header {
    background-color:  #cccccc;
    border: solid 1px #333333;
    padding-left:  0.2em;
    padding-right: 0.2em;
}
.uncovered {
    background-color:  #ff9999;
    border: solid 1px #cc0000;
}
.covered75 {
    background-color:  #ffcc99;
    border: solid 1px #ff9933;
}
.covered90 {
    background-color:  #ffff99;
    border: solid 1px #cccc66;
}
.covered {
    background-color:  #99ff99;
    border: solid 1px #009900;
}

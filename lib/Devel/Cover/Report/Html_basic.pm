# Copyright 2001-2004, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Report::Html_basic;

use strict;
use warnings;

our $VERSION = "0.51";

use Devel::Cover::DB 0.51;

use Template 2.00;

my $Template;
my %Filenames;
my %File_exists;

sub print_stylesheet
{
    my ($db) = @_;
    my $file = "$db->{db}/cover.css";
    open CSS, '>', $file or return;
    my $p = tell DATA;
    print CSS <DATA>;
    seek DATA, $p, 0;
    close CSS;
}

sub print_summary
{
    my ($db, $options) = @_;

    my @showing = grep $options->{show}{$_}, $db->all_criteria;
    my @headers = map { ($db->all_criteria_short)[$_] }
                  grep { $options->{show}{($db->all_criteria)[$_]} }
                  (0 .. $db->all_criteria - 1);
    my @files   = (grep($db->{summary}{$_}, @{$options->{file}}), "Total");

    my %vals;

    for my $file (@files)
    {
        my %pvals;
        my $part = $db->{summary}{$file};
        for my $criterion (@showing)
        {
            my $pc = exists $part->{$criterion}
                ? sprintf "%4.1f", $part->{$criterion}{percentage}
                : "n/a";

            my $bg = "";
            if ($pc ne "n/a")
            {
                if ($criterion ne 'time') {
                    $vals{$file}{$criterion}{class} = cvg_class($pc);
                }
                if (exists $Filenames{$file}) {
                    if ($criterion eq 'branch') {
                        $vals{$file}{$criterion}{link} = "$Filenames{$file}--branch.html";
                    }
                    elsif ($criterion eq 'condition') {
                        $vals{$file}{$criterion}{link} = "$Filenames{$file}--condition.html";
                    }
                    elsif ($criterion eq 'subroutine') {
                        $vals{$file}{$criterion}{link} = "$Filenames{$file}--subroutine.html";
                    }
                }
            }
            $vals{$file}{$criterion}{pc} = $pc;
            $vals{$file}{$criterion}{bg} = $bg;
        }
    }

    my $vars =
    {
        title       => "Coverage Summary",
        dbname      => $db->{db},
        showing     => \@showing,
        headers     => \@headers,
        files       => \@files,
        filenames   => \%Filenames,
        file_exists => \%File_exists,
        vals        => \%vals,
    };

    my $html = "$options->{outputdir}/coverage.html";
    $Template->process("summary", $vars, $html) or die $Template->error();

    print "HTML output sent to $html\n";
}

sub print_file
{
    my ($db, $file, $options) = @_;

    my @lines;
    my $cover = $db->cover;
    my @showing = grep $options->{show}{$_}, $db->criteria;
    my @headers = map { ($db->all_criteria_short)[$_] }
                  grep { $options->{show}{($db->criteria)[$_]} }
                  (0 .. $db->criteria - 1);

    my $f = $cover->file($file);

    open F, $file or warn("Unable to open $file: $!\n"), next;
    LINE: while (defined(my $l = <F>))
    {
        my $n = $.;
        chomp $l;

        my %criteria;
        for my $c (@showing)
        {
            my $criterion = $f->$c();
            if ($criterion)
            {
                my $l = $criterion->location($n);
                $criteria{$c} = $l ? [@$l] : $l;
            }
        }

        my $count = 0;
        my $more  = 1;
        while ($more)
        {
            my %line;

            $count++;
            $line{number} = $n;
            $line{text}   = $l;

            my $error = 0;
            $more = 0;
            for my $c (@showing)
            {
                my $o = shift @{$criteria{$c}};
                $more ||= @{$criteria{$c}};
                my $details = $c !~ /statement|pod|time/;
                my $text = $o ? $details ? $o->percentage : $o->covered : "";
                my $bg = $o ? $o->error ? "error" : "ok" : "default";
                my %criterion = ( text => $text, bg => $bg );
                $criterion{link} = "$Filenames{$file}--$c.html#$n-$count"
                    if $details;
                push @{$line{criteria}}, \%criterion;
                $error ||= $o->error if $o;
            }

            $line{bg} = $error ? "error" : "default";

            push @lines, \%line;

            last LINE if $l =~ /^__(END|DATA)__/;
            $n = $l = "";
        }
    }
    close F or die "Unable to close $file: $!";

    my $vars =
    {
        title       => "Coverage report for $file",
        showing     => \@showing,
        headers     => \@headers,
        filenames   => \%Filenames,
        file_exists => \%File_exists,
        lines       => \@lines,
    };

    my $html = "$options->{outputdir}/$Filenames{$file}.html";
    $Template->process("file", $vars, $html) or die $Template->error();
}

sub print_branches
{
    my ($db, $file, $options) = @_;

    my $branches = $db->cover->file($file)->branch;

    return unless $branches;

    my @branches;
    for my $location (sort { $a <=> $b } $branches->items)
    {
        my $count = 0;
        for my $b (@{$branches->location($location)})
        {
            $count++;
            push @branches,
                {
                    ref        => "$location-$count",
                    number     => $count == 1 ? $location : "",
                    bg         => $b->error ? "error" : "ok",
                    percentage => $b->percentage,
                    parts      => [ map {text => $_, bg => $_ ? "ok" : "error"},
                                        $b->values ],
                    text       => $b->text,
                };
        }
    }

    my $vars =
    {
        title    => "Branch coverage report for $file",
        branches => \@branches,
    };

    my $html = "$options->{outputdir}/$Filenames{$file}--branch.html";
    $Template->process("branches", $vars, $html) or die $Template->error();
}

sub print_conditions
{
    my ($db, $file, $options) = @_;

    my $conditions = $db->cover->file($file)->condition;

    return unless $conditions;

    my %r;
    for my $location (sort { $a <=> $b } $conditions->items)
    {
        my $count = 0;
        for my $c (@{$conditions->location($location)})
        {
            $count++;
            push @{$r{$c->type}},
                {
                    ref        => "$location-$count",
                    number     => $count == 1 ? $location : "",
                    condition  => $c,
                    bg         => $c->error ? "error" : "ok",
                    percentage => $c->percentage,
                    parts      => [ map {text => $c->value($_),
                                         bg   => $c->error($_) ? "error" : "ok"},
                                        0 .. $c->total - 1 ],
                    text       => $c->text,
                };
        }
    }

    my @types = map
        {
            name       => do { my $n = $_; $n =~ s/_/ /g; $n },
            headers    => $r{$_}[0]{condition}->headers,
            conditions => $r{$_},
        }, sort keys %r;

    my $vars =
    {
        title  => "Condition coverage report for $file",
        types  => \@types,
    };

    # use Data::Dumper;
    # print Dumper $vars;

    my $html = "$options->{outputdir}/$Filenames{$file}--condition.html";
    $Template->process("conditions", $vars, $html)
        or die $Template->error();
}

sub report
{
    my ($pkg, $db, $options) = @_;

    $Template = Template->new
    ({
        LOAD_TEMPLATES =>
        [
            Devel::Cover::Report::Html_basic::Template::Provider->new({}),
        ],
    });

    %Filenames   = map { $_ => do { (my $f = $_) =~ s/\W/-/g; $f } }
                       @{$options->{file}};
    %File_exists = map { $_ => -e } @{$options->{file}};

    print_stylesheet($db);
    print_summary($db, $options);

    for my $file (@{$options->{file}})
    {
        print_file      ($db, $file, $options);
        print_branches  ($db, $file, $options) if $options->{show}{branch};
        print_conditions($db, $file, $options) if $options->{show}{condition};
    }
}

1;

package Devel::Cover::Report::Html_basic::Template::Provider;

use strict;
use warnings;

our $VERSION = "0.51";

use base "Template::Provider";

my %Templates;

sub fetch
{
    my $self = shift;
    my ($name) = @_;
    # print "Looking for <$name>\n";
    $self->SUPER::fetch(exists $Templates{$name} ? \$Templates{$name} : $name)
}

$Templates{html} = <<'EOT';
<!--

This file was generated by Devel::Cover Version 0.51

Devel::Cover is copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

Devel::Cover is free.  It is licensed under the same terms as Perl itself.

The latest version of Devel::Cover should be available from my homepage:
http://www.pjcj.net

-->

<?xml version="1.0" encoding="utf-8"?>
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

<h1>[% title %]</h1>
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
                [% IF vals.$file.$criterion.link.defined %]
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

<h1> [% title %] </h1>

<table>

    <tr align="RIGHT" valign="CENTER">
        <th> line </th>
        <th> % </th>
        <th> true </th>
        <th> false </th>
        <th align="CENTER"> branch </th>
    </tr>

    [% FOREACH branch = branches %]
        <a name="[% branch.ref %]"> </a>
        <tr align="RIGHT" valign="CENTER">
            <td [% bg(colour = "number") %]> [% branch.number %] </td>
            <td [% bg(colour = branch.bg) %]> [% branch.percentage %] </td>
            [% FOREACH part = branch.parts %]
                <td [% bg(colour = part.bg) %]> [% part.text %] </td>
            [% END %]
            <td [% bg(colour = branch.bg) %] align="LEFT">
                <pre> [% branch.text %]</pre>
            </td>
        </tr>
    [% END %]

</table>

[% END %]
EOT

$Templates{conditions} = <<'EOT';
[% WRAPPER html %]

<h1> [% title %] </h1>

[% FOREACH type = types %]

    <h2> [% type.name %] conditions </h2>

    <table>

        <tr align="RIGHT" valign="CENTER">
            <th> line </th>
            <th> % </th>
            [% FOREACH header = type.headers %]
                <th> [% header %] </th>
            [% END %]
            <th align="CENTER"> condition </th>
        </tr>

        [% FOREACH condition = type.conditions %]
            <a name="[% condition.ref %]"> </a>
            <tr align="RIGHT" valign="CENTER">
                <td [% bg(colour = "number") %]> [% condition.number %] </td>
                <td [% bg(colour = condition.bg) %]>
                    [% condition.percentage %]
                </td>
                [% FOREACH part = condition.parts %]
                    <td [% bg(colour = part.bg) %]> [% part.text %] </td>
                [% END %]
                <td [% bg(colour = condition.bg) %] align="LEFT">
                    <pre> [% condition.text %]</pre>
                </td>
            </tr>
        [% END %]

    </table>

[% END %]

[% END %]
EOT

$Templates{file} = <<'EOT';
[% WRAPPER html %]

<h1> [% title %] </h1>

<table>

    <tr align="RIGHT" valign="CENTER">
        <th> </th>
        [% FOREACH header = headers %]
            <th> [% header %] </th>
        [% END %]
        <th align="CENTER"> code </th>
    </tr>

    [% FOREACH line = lines %]
        <tr align="RIGHT" valign="CENTER">
            <td [% bg(colour = "number") %]> [% line.number %] </td>
            [% FOREACH cr = line.criteria %]
                <td [% bg(colour = cr.bg) %]>
                    [% IF cr.link.defined && cr.text %]
                    <a href="[% cr.link %]">
                    [% END %]
                    [% cr.text %]
                    [% IF cr.link.defined && cr.text %]
                    </a>
                    [% END %]
                </td>
            [% END %]
            <td [% bg(colour = line.bg) %] align="LEFT">
                <pre> [% line.text %]</pre>
            </td>
        </tr>
    [% END %]

</table>

[% END %]
EOT

# remove some whitespace from templates
s/^\s+//gm for values %Templates;

1;

=head1 NAME

Devel::Cover::Report::Html_basic - Backend for HTML reporting of coverage
statistics

=head1 SYNOPSIS

 use Devel::Cover::Report::Html_basic;

 Devel::Cover::Report::Html_basic->report($db, $options);

=head1 DESCRIPTION

This module provides a HTML reporting mechanism for coverage data.  It
is designed to be called from the C<cover> program.

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 VERSION

Version 0.51 - 29th November 2004

=head1 LICENCE

Copyright 2001-2004, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

package Devel::Cover::Report::Html_basic;

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
/*    border-collapse: collapse;*/
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

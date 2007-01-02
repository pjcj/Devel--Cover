# Copyright 2001-2007, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Report::Html_basic;

use strict;
use warnings;

our $VERSION = "0.60";

use Devel::Cover::DB 0.60;

use Getopt::Long;
use Template 2.00;

my ($HAVE_HIGHLIGHTER,$HAVE_PPI,$HAVE_PERLTIDY);
BEGIN {
    eval "use PPI; use PPI::HTML;";
    $HAVE_PPI = !$@;
    eval "use Perl::Tidy";
    $HAVE_PERLTIDY = !$@;
    $HAVE_HIGHLIGHTER = $HAVE_PPI || $HAVE_PERLTIDY;
}

my $Template;
my %R;

sub print_stylesheet
{
    my $file = "$R{options}{outputdir}/cover.css";
    open CSS, '>', $file or return;
    my $p = tell DATA;
    print CSS <DATA>;
    seek DATA, $p, 0;
    close CSS;
}

sub oclass
{
    my ($o, $criterion) = @_;
    $o ? class($o->percentage, $o->error, $criterion) : ""
}

sub class
{
    my ($pc, $err, $criterion) = @_;
    return "" if $criterion eq "time";
    !$err ? "c3"
          : $pc <  75 ? "c0"
          : $pc <  90 ? "c1"
          : $pc < 100 ? "c2"
          : "c3"
}

sub get_summary
{
    my ($file, $criterion) = @_;

    my %vals;
    @vals{"pc", "class"} = ("n/a", "");

    my $part = $R{db}->summary($file);
    return \%vals unless exists $part->{$criterion};
    my $c = $part->{$criterion};
    $vals{class} = class($c->{percentage}, $c->{error}, $criterion);

    return \%vals unless defined $c->{percentage};
    $vals{pc}       = sprintf "%4.1f", $c->{percentage};
    $vals{covered}  = $c->{covered} || 0;
    $vals{total}    = $c->{total};
    $vals{details}  = "$vals{covered} / $vals{total}";

    my $cr = $criterion eq "pod" ? "subroutine" : $criterion;
    return \%vals
      if $cr !~ /^branch|condition|subroutine$/ || !exists $R{filenames}{$file};
    $vals{link} = "$R{filenames}{$file}--$cr.html";

    \%vals
};

sub print_summary
{
    my $vars =
    {
        R     => \%R,
        files => [ grep($R{db}->summary($_), @{$R{options}{file}}), "Total" ],
    };

    my $html = "$R{options}{outputdir}/$R{options}{option}{outputfile}";
    $Template->process("summary", $vars, $html) or die $Template->error();

    $html
}

sub _highlight_ppi {
    my @all_lines = @_;
    my $code = join "", @all_lines;
    my $document = PPI::Document->new(\$code);
    my $highlight = PPI::HTML->new(line_numbers => 1);
    my $pretty =  $highlight->html($document);

    my $split = '<span class="line_number">';

    # turn significant whitespace into &nbsp;
    @all_lines = map {
        $_ =~ s{</span>( +)}{"</span>" . ("&nbsp;" x length($1))}e;
        "$split$_";
    } split /$split/, $pretty;

    # remove the line number
    @all_lines = map {
        s{<span class="line_number">.*?</span>}{}; $_;
    } @all_lines;
    @all_lines = map {
        s{<span class="line_number">}{}; $_;
    } @all_lines;

    # remove the BR
    @all_lines = map {
        s{<br>$}{}; $_;
    } @all_lines;
    @all_lines = map {
        s{<br>\n</span>}{</span>}; $_;
    } @all_lines;

    shift @all_lines if $all_lines[0] eq "";
    return @all_lines;
}

sub _highlight_perltidy {
    my @all_lines = @_;
    my @coloured = ();

    Perl::Tidy::perltidy(
        source      => \@all_lines, 
        destination => \@coloured, 
        argv        => '-html -pre -nopod2html', 
        stderr      => '-',
        errorfile   => '-',
    );

    # remove the PRE
    shift @coloured;
    pop @coloured;
    @coloured = grep { !/<a name=/ } @coloured;

    return @coloured
}

*_highlight = $HAVE_PPI      ? \&_highlight_ppi
            : $HAVE_PERLTIDY ? \&_highlight_perltidy
            : sub {};

sub print_file
{
    my @lines;
    my $f = $R{db}->cover->file($R{file});

    open F, $R{file} or warn("Unable to open $R{file}: $!\n"), return;
    my @all_lines = <F>;

    @all_lines = _highlight(@all_lines) if $HAVE_HIGHLIGHTER;

    my $linen = 1;
    LINE: while (defined(my $l = shift @all_lines))
    {
        my $n  = $linen++;
        chomp $l;

        my %criteria;
        for my $c (@{$R{showing}})
        {
            my $criterion = $f->$c();
            if ($criterion)
            {
                my $l = $criterion->location($n);
                $criteria{$c} = $l ? [@$l] : undef;
            }
        }

        my $count = 0;
        my $more  = 1;
        while ($more)
        {
            my %line;

            $count++;
            $line{number} = length $n ? $n : "&nbsp;";
            $line{text}   = length $l ? $l : "&nbsp;";

            my $error = 0;
            $more = 0;
            for my $ann (@{$R{options}{annotations}})
            {
                for my $a (0 .. $ann->count - 1)
                {
                    my $text = $ann->text ($R{file}, $n, $a);
                    $text = "&nbsp;" unless $text && length $text;
                    push @{$line{criteria}},
                    {
                        text  => $text,
                        class => $ann->class($R{file}, $n, $a),
                    };
                    $error ||= $ann->error($R{file}, $n, $a);
                }
            }
            for my $c (@{$R{showing}})
            {
                my $o = shift @{$criteria{$c}};
                $more ||= @{$criteria{$c}};
                my $link = $c !~ /statement|time/;
                my $pc = $link && $c !~ /subroutine|pod/;
                my $text = $o ? $pc ? $o->percentage : $o->covered : "&nbsp;";
                my %criterion = ( text => $text, class => oclass($o, $c) );
                my $cr = $c eq "pod" ? "subroutine" : $c;
                $criterion{link} = "$R{filenames}{$R{file}}--$cr.html#$n-$count"
                    if $o && $link;
                push @{$line{criteria}}, \%criterion;
                $error ||= $o->error if $o;
            }

            push @lines, \%line;

            last LINE if $l =~ /^__(END|DATA)__/;
            $n = $l = "";
        }
    }
    close F or die "Unable to close $R{file}: $!";

    my $vars =
    {
        R     => \%R,
        lines => \@lines,
    };

    my $html = "$R{options}{outputdir}/$R{filenames}{$R{file}}.html";
    $Template->process("file", $vars, $html) or die $Template->error();
}

sub print_branches
{
    my $branches = $R{db}->cover->file($R{file})->branch;
    return unless $branches;

    my @branches;
    for my $location (sort { $a <=> $b } $branches->items)
    {
        my $count = 0;
        for my $b (@{$branches->location($location)})
        {
            $count++;
            my $text = $b->text;
            ($text) = _highlight($text) if $HAVE_HIGHLIGHTER;

            push @branches,
                {
                    number     => $count == 1 ? $location : "",
                    parts      =>
                    [
                        map { text  => $b->value($_),
                              class => class($b->value($_), $b->error($_),
                                             "branch") },
                            0 .. $b->total - 1
                    ],
                    text       => $text,
                };
        }
    }

    my $vars =
    {
        R        => \%R,
        branches => \@branches,
    };

    my $html = "$R{options}{outputdir}/$R{filenames}{$R{file}}--branch.html";
    $Template->process("branches", $vars, $html) or die $Template->error();
}

sub print_conditions
{
    my $conditions = $R{db}->cover->file($R{file})->condition;
    return unless $conditions;

    my %r;
    for my $location (sort { $a <=> $b } $conditions->items)
    {
        my %count;
        for my $c (@{$conditions->location($location)})
        {
            $count{$c->type}++;
            # print "-- [$count{$c->type}][@{[$c->text]}]}]\n";
            my $text = $c->text;
            ($text) = _highlight($text) if $HAVE_HIGHLIGHTER;

            push @{$r{$c->type}},
                {
                    number     => $count{$c->type} == 1 ? $location : "",
                    condition  => $c,
                    parts      =>
                    [
                        map { text  => $c->value($_),
                              class => class($c->value($_), $c->error($_),
                                             "condition") },
                            0 .. $c->total - 1
                    ],
                    text       => $text,
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
        R     => \%R,
        types => \@types,
    };

    # use Data::Dumper; print Dumper \@types;

    my $html = "$R{options}{outputdir}/$R{filenames}{$R{file}}--condition.html";
    $Template->process("conditions", $vars, $html) or die $Template->error();
}

sub print_subroutines
{
    my $subroutines = $R{db}->cover->file($R{file})->subroutine;
    return unless $subroutines;
    my $s = $R{options}{show}{subroutine};

    my $pods;
    $pods = $R{db}->cover->file($R{file})->pod if $R{options}{show}{pod};

    my $subs;
    for my $line (sort { $a <=> $b } $subroutines->items)
    {
        my @p;
        if ($pods)
        {
            my $l = $pods->location($line);
            @p = @$l if $l;
        }
        for my $o (@{$subroutines->location($line)})
        {
            my $p = shift @p;
            push @$subs,
            {
                line   => $line,
                name   => $o->name,
                count  => $s ? $o->covered : "",
                class  => $s ? oclass($o, "subroutine") : "",
                pod    => $p ? $p->covered ? "Yes" : "No" : "n/a",
                pclass => $p ? oclass($p, "pod") : "",
            };
        }
    }

    my $vars =
    {
        R    => \%R,
        subs => $subs,
    };

    my $html =
        "$R{options}{outputdir}/$R{filenames}{$R{file}}--subroutine.html";
    $Template->process("subroutines", $vars, $html) or die $Template->error();
}

sub get_options
{
    my ($self, $opt) = @_;
    $opt->{option}{outputfile} = "coverage.html";
    die "Invalid command line options" unless
        GetOptions($opt->{option},
                   qw(
                       outputfile=s
                     ));
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

    %R =
    (
        db      => $db,
        options => $options,
        showing => [ grep $options->{show}{$_}, $db->criteria ],
        headers =>
        [
            map { ($db->criteria_short)[$_] }
                grep { $options->{show}{($db->criteria)[$_]} }
                     (0 .. $db->criteria - 1)
        ],
        annotations =>
        [
            map { my $a = $_; map $a->header($_), 0 .. $a->count - 1 }
                @{$options->{annotations}}
        ],
        filenames =>
        {
            map { $_ => do { (my $f = $_) =~ s/\W/-/g; $f } }
                @{$options->{file}}
        },
        exists      => { map { $_ => -e } @{$options->{file}} },
        get_summary => \&get_summary,
    );

    print_stylesheet;
    my $html = print_summary;

    for (@{$options->{file}})
    {
        $R{file} = $_;
        my $show = $options->{show};
        print_file;
        print_branches    if $show->{branch};
        print_conditions  if $show->{condition};
        print_subroutines if $show->{subroutine} || $show->{pod};
    }

    print "HTML output sent to $html\n";
}

1;

package Devel::Cover::Report::Html_basic::Template::Provider;

use strict;
use warnings;

our $VERSION = "0.60";

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
<!DOCTYPE html
     PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
     "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<!--
This file was generated by Devel::Cover Version 0.60
Devel::Cover is copyright 2001-2006, Paul Johnson (pjcj\@cpan.org)
Devel::Cover is free. It is licensed under the same terms as Perl itself.
The latest version of Devel::Cover should be available from my homepage:
http://www.pjcj.net
-->
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"></meta>
    <meta http-equiv="Content-Language" content="en-us"></meta>
    <link rel="stylesheet" type="text/css" href="cover.css"></link>
    <title> [% title %] </title>
</head>
<body>
    [% content %]
</body>
</html>
EOT

$Templates{header} = <<'EOT';
<table>
    <tr>
        <th colspan="4">[% R.file %]</th>
    </tr>
    <tr class="hblank"><td class="dblank"></td></tr>
    <tr>
        <th class="hh">Criterion</th>
        <th class="hh">Covered</th>
        <th class="hh">Total</th>
        <th class="hh">%</th>
    </tr>
    [% FOREACH criterion = criteria %]
        [% vals = R.get_summary(R.file, criterion) %]
        <tr>
            <td class="h">[% criterion %]</td>
            <td>[% vals.covered %]</td>
            <td>[% vals.total %]</td>
            <td [% IF vals.class %]class="[% vals.class %]" [% END %]title="[% vals.details %]">
                [% IF vals.link.defined %]
                    <a href="[% vals.link %]"> [% vals.pc %] </a>
                [% ELSE %]
                    [% vals.pc %]
                [% END %]
            </td>
        </tr>
    [% END %]
</table>
<div><br></br></div>
EOT

$Templates{summary} = <<'EOT';
[% WRAPPER html %]

<h1> Coverage Summary </h1>
<table>
    <tr>
        <td class="h" align="right">Database:</td>
        <td>[% R.db.db %]</td>
    </tr>
</table>
<div><br></br></div>
<table>
    <tr>
    <th> file </th>
    [% FOREACH header = R.headers %]
        <th> [% header %] </th>
    [% END %]
    <th> total </th>
    </tr>

    [% FOREACH file = files %]
        <tr align="center" valign="top">
            <td align="left">
                [% IF R.exists.$file %]
                   <a href="[% R.filenames.$file %].html"> [% file %] </a>
                [% ELSE %]
                    [% file %]
                [% END %]
            </td>

            [% FOREACH criterion = R.showing %]
                [% vals = R.get_summary(file, criterion) %]
                [% IF vals.class %]
                    <td class="[% vals.class %]" title="[% vals.details %]">
                [% ELSE %]
                    <td>
                [% END %]
                [% IF vals.link.defined %]
                    <a href="[% vals.link %]"> [% vals.pc %] </a>
                [% ELSE %]
                    [% vals.pc %]
                [% END %]
                </td>
            [% END %]

            [% vals = R.get_summary(file, "total") %]
            <td class="[% vals.class %]" title="[% vals.details %]">
                [% vals.pc %]
            </td>
        </tr>
    [% END %]
</table>

[% END %]
EOT

$Templates{file} = <<'EOT';
[% WRAPPER html %]

<h1> File Coverage </h1>

[%
   crit = [];
   FOREACH criterion = R.showing;
       crit.push(criterion) UNLESS criterion == "time";
   END;
   crit.push("total");
   PROCESS header criteria = crit;
%]

<table>
    <tr>
        <th> line </th>
        [% FOREACH header = R.annotations.merge(R.headers) %]
            <th> [% header %] </th>
        [% END %]
        <th> code </th>
    </tr>

    [% FOREACH line = lines %]
        <tr>
            <td [% IF line.number %] class="h" [% END %]>
                <a [% IF line.number != '&nbsp;' %]name="[% line.number %]"[% END %]>[% line.number %]</a>
            </td>
            [% FOREACH cr = line.criteria %]
                <td [% IF cr.class %] class="[% cr.class %]" [% END %]>
                    [% IF cr.link.defined %] <a href="[% cr.link %]"> [% END %]
                    [% cr.text %]
                    [% IF cr.link.defined %] </a> [% END %]
                </td>
            [% END %]
            <td class="s"> [% line.text %] </td>
        </tr>
    [% END %]
</table>

[% END %]
EOT

$Templates{branches} = <<'EOT';
[% WRAPPER html %]

<h1> Branch Coverage </h1>

[% PROCESS header criteria = [ "branch" ] %]

<table>
    <tr>
        <th> line </th>
        <th> true </th>
        <th> false </th>
        <th> branch </th>
    </tr>

    [% FOREACH branch = branches %]
        <a name="[% branch.ref %]"> </a>
        <tr>
            <td class="h"> [% branch.number %] </td>
            [% FOREACH part = branch.parts %]
                <td class="[% part.class %]"> [% part.text %] </td>
            [% END %]
            <td class="s"> [% branch.text %] </td>
        </tr>
    [% END %]
</table>

[% END %]
EOT

$Templates{conditions} = <<'EOT';
[% WRAPPER html %]

<h1> Condition Coverage </h1>

[% PROCESS header criteria = [ "condition" ] %]

[% FOREACH type = types %]
    <h2> [% type.name %] conditions </h2>

    <table>
        <tr>
            <th> line </th>
            [% FOREACH header = type.headers %]
                <th> [% header %] </th>
            [% END %]
            <th> condition </th>
        </tr>

        [% FOREACH condition = type.conditions %]
            <a name="[% condition.ref %]"> </a>
            <tr>
                <td class="h"> [% condition.number %] </td>
                [% FOREACH part = condition.parts %]
                    <td class="[% part.class %]"> [% part.text %] </td>
                [% END %]
                <td class="s"> [% condition.text %] </td>
            </tr>
        [% END %]
    </table>
[% END %]

[% END %]
EOT

$Templates{subroutines} = <<'EOT';
[% WRAPPER html %]

<h1> Subroutine Coverage </h1>

[%
   crit = [];
   crit.push("subroutine") IF R.options.show.subroutine;
   crit.push("pod")        IF R.options.show.pod;
   PROCESS header criteria = crit;
%]

<table>
    <tr>
        <th> line </th>
        [% IF R.options.show.subroutine %]
            <th> count </th>
        [% END %]
        [% IF R.options.show.pod %]
            <th> pod </th>
        [% END %]
        <th> subroutine </th>
    </tr>
    [% FOREACH sub = subs %]
        <tr>
            <td class="h"> [% sub.line %] </td>
            [% IF R.options.show.subroutine %]
                <td class="[% sub.class %]"> [% sub.count %] </td>
            [% END %]
            [% IF R.options.show.pod %]
                <td class="[% sub.pclass %]"> [% sub.pod %] </td>
            [% END %]
            <td> [% sub.name %] </td>
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
is designed to be called from the C<cover> program. It will add syntax
highlighting if C<PPI::HTML> or C<Perl::Tidy> is installed.

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 VERSION

Version 0.60 - 2nd January 2007

=head1 LICENCE

Copyright 2001-2007, Paul Johnson (pjcj@cpan.org)

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
    text-align : center;
    background-color: #cc99ff;
    border: solid 1px #999999;
    padding: 0.2em;
    -moz-border-radius: 10px;
}

a {
    color: #000000;
}
a:visited {
    color: #333333;
}

table {
    border-spacing: 0px;
}
tr {
    text-align : center;
    vertical-align: top;
}
th,.h,.hh {
    background-color: #cccccc;
    border: solid 1px #333333;
    padding: 0em 0.2em;
    width: 2.5em;
    -moz-border-radius: 4px;
}
.hh {
    width: 25%;
}
td {
    border: solid 1px #cccccc;
    border-top: none;
    border-left: none;
    -moz-border-radius: 4px;
}
.hblank {
    height: 0.5em;
}
.dblank {
    border: none;
}

/* source code */
pre,.s {
    text-align: left;
    font-family: monospace;
    white-space: pre;
    padding: 0.2em 0.5em 0em 0.5em;
}

/* Classes for color-coding coverage information:
 *   c0  : path not covered or coverage < 75%
 *   c1  : coverage >= 75%
 *   c2  : coverage >= 90%
 *   c3  : path covered or coverage = 100%
 */
.c0 {
    background-color: #ff9999;
    border: solid 1px #cc0000;
}
.c1 {
    background-color: #ffcc99;
    border: solid 1px #ff9933;
}
.c2 {
    background-color: #ffff99;
    border: solid 1px #cccc66;
}
.c3 {
    background-color: #99ff99;
    border: solid 1px #009900;
}

/* For syntax highlighting with PPI::HTML */
.line_number { color: #aaaaaa; }
.comment  { color: #228B22; }
.symbol  { color: #00688B; }
.word { color: #8B008B; font-weight:bold; }
.pragma { color: #8B008B; font-weight:bold; }
.structure { color: #000000; }
.number { color: #B452CD; }
.single  { color: #CD5555;}
.double  { color: #CD5555;}
.match   { color: #CD5555;}
.substitute { color: #CD5555;}
.heredoc_content { color: #CD5555;}
.interpolate { color: #CD5555;}
.words { color: #CD5555;}

/* for syntax highlighting with Perl::Tidy */
.c  { color: #228B22;                    } /* comment */
.cm { color: #000000;                    } /* comma */
.co { color: #000000;                    } /* colon */
.h  { color: #CD5555; font-weight:bold;  } /* here-doc-target */
.hh { color: #CD5555; font-style:italic; } /* here-doc-text */
.i  { color: #00688B;                    } /* identifier */
.j  { color: #000000; font-weight:bold;  } /* label */
.k  { color: #8B4513; font-weight:bold;  } /* keyword */
.m  { color: #FF0000; font-weight:bold;  } /* subroutine */
.n  { color: #B452CD;                    } /* numeric */
.p  { color: #000000;                    } /* paren */
.pd { color: #228B22; font-style:italic; } /* pod-text */
.pu { color: #000000;                    } /* punctuation */
.q  { color: #CD5555;                    } /* quote */
.s  { color: #000000;                    } /* structure */
.sc { color: #000000;                    } /* semicolon */
.v  { color: #B452CD;                    } /* v-string */
.w  { color: #000000;                    } /* bareword */

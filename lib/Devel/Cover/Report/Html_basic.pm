# Copyright 2001-2024, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Report::Html_basic;

use strict;
use warnings;

our $VERSION;
BEGIN {
# VERSION
}

use Devel::Cover::DB;
use Devel::Cover::Html_Common "launch";
use Devel::Cover::Inc;
use Devel::Cover::Web "write_file";

BEGIN { $VERSION //= $Devel::Cover::Inc::VERSION }

use HTML::Entities;
use Getopt::Long;
use Template 2.00;

my ($Have_highlighter, $Have_PPI, $Have_perltidy);

BEGIN {
    eval "use PPI; use PPI::HTML;";
    $Have_PPI = !$@;
    eval "use Perl::Tidy";
    $Have_perltidy = !$@;
    $Have_highlighter = $Have_PPI || $Have_perltidy;
}

my $Template;
my %R;

sub oclass {
    my ($o, $criterion) = @_;
    $o ? class($o->percentage, $o->error, $criterion) : ""
}

my $threshold = { c0 => 75, c1 => 90, c2 => 100 };

sub class {
    my ($pc, $err, $criterion) = @_;
    return "" if $criterion eq "time";
    no warnings "uninitialized";
      !$err                  ? "c3"
    : $pc < $threshold->{c0} ? "c0"
    : $pc < $threshold->{c1} ? "c1"
    : $pc < $threshold->{c2} ? "c2"
    :                          "c3"
}

sub get_summary {
    my ($file, $criterion) = @_;

    my %vals;
    @vals{"pc", "class"} = ("n/a", "");

    my $part = $R{db}->summary($file);
    return \%vals unless exists $part->{$criterion};
    my $c = $part->{$criterion};
    $vals{class} = class($c->{percentage}, $c->{error}, $criterion);

    return \%vals unless defined $c->{percentage};
    $vals{pc} = do { my $x = sprintf "%5.2f", $c->{percentage}; chop $x; $x };
    $vals{covered}  = $c->{covered} || 0;
    $vals{total}    = $c->{total};
    $vals{details}  = "$vals{covered} / $vals{total}";

    my $cr = $criterion eq "pod" ? "subroutine" : $criterion;
    return \%vals if $cr !~ /^branch|condition|subroutine$/ ||
                     !exists $R{filenames}{$file};
    $vals{link} = "$R{filenames}{$file}--$cr.html";

    \%vals
};

sub print_summary {
    my $vars = {
        R     => \%R,
        files => [ "Total", grep $R{db}->summary($_), @{$R{options}{file}} ],
    };

    my $html = "$R{options}{outputdir}/$R{options}{option}{outputfile}";
    $Template->process("summary", $vars, $html) or die $Template->error();

    $html
}

sub _highlight_ppi {
    my @all_lines = @_;
    my $code      = join "", @all_lines;
    my $document  = PPI::Document->new(\$code);
    my $highlight = PPI::HTML->new(line_numbers => 1);
    my $pretty    = $highlight->html($document);

    my $split     = '<span class="line_number">';

    no warnings "uninitialized";

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

    @all_lines
}

sub _highlight_perltidy {
    my @all_lines = @_;
    my @coloured;

    my ($stderr, $errorfile);
    Perl::Tidy::perltidy(
        source      => \@all_lines,
        destination => \@coloured,
        argv        => "-html -pre -nopod2html",
        stderr      => \$stderr,
        errorfile   => \$errorfile,
    );

    # remove the PRE
    shift @coloured;
    pop @coloured;
    @coloured = grep { !/<a name=/ } @coloured;

    @coloured
}

sub _highlight {
    if ($Have_PPI && !$R{options}{option}{noppihtml}) {
        return _highlight_ppi(@_);
    } else {
        if ($Have_perltidy && !$R{options}{option}{noperltidy}) {
            return _highlight_perltidy(@_);
        }
    }

    return;
}

sub print_file {
    my @lines;
    my $f = $R{db}->cover->file($R{file});

    open F, $R{file} or warn("Unable to open $R{file}: $!\n"), return;
    my @all_lines = <F>;

    if (!($R{options}{option}{noppihtml} && $R{options}{option}{noperltidy})) {
        @all_lines = _highlight(@all_lines) if $Have_highlighter;
    }

    my $linen = 1;
    LINE: while (defined(my $l = shift @all_lines)) {
        my $n  = $linen++;
        chomp $l;

        my %criteria;
        for my $c (@{$R{showing}}) {
            my $criterion = $f->$c();
            if ($criterion) {
                my $l = $criterion->location($n);
                $criteria{$c} = $l ? [@$l] : undef;
            }
        }

        my $count = 0;
        my $more  = 1;
        while ($more) {
            my %line;

            $count++;
            $line{number} = length $n ? $n : "&nbsp;";
            $line{text}   = length $l ? $l : "&nbsp;";

            my $error = 0;
            $more = 0;
            for my $ann (@{$R{options}{annotations}}) {
                for my $a (0 .. $ann->count - 1) {
                    my $text = $ann->text ($R{file}, $n, $a);
                    $text = "&nbsp;" unless $text && length $text;
                    push @{$line{criteria}}, {
                        text  => $text,
                        class => $ann->class($R{file}, $n, $a),
                    };
                    $error ||= $ann->error($R{file}, $n, $a);
                }
            }
            for my $c (@{$R{showing}}) {
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

    # Add forward references to uncovered lines ...
    # first line has a ref to the first uncovered line unless
    # the first line already is uncovered in which case it links
    # to the *next* uncovered line
    {
        my @unc = grep { $_->{criteria}[0]{class} eq "c0" &&
            $_->{criteria}[0]{text}  eq  "0" } @lines;
        while (@unc) {
            my $u = pop @unc;
            my $link = "#" . $u->{number};
            (@unc ? $unc[-1] : $lines[0])->{criteria}[0]{link} ||= $link;
        }
    }

    my $vars = {
        R     => \%R,
        lines => \@lines,
    };

    $Template->process("file", $vars, $R{file_html}) or die $Template->error();
}

sub print_branches {
    my $branches = $R{db}->cover->file($R{file})->branch;
    return unless $branches;

    my @branches;
    for my $location (sort { $a <=> $b } $branches->items) {
        my $count = 0;
        for my $b (@{$branches->location($location)}) {
            $count++;
            my $text = $b->text;
            ($text) = _highlight($text) if $Have_highlighter;

            push @branches,
                {
                    number => $count == 1 ? $location : "",
                    parts  => [
                        map { text  => $b->value($_),
                              class => class($b->value($_), $b->error($_),
                                             "branch") },
                            0 .. $b->total - 1
                    ],
                    text   => $text,
                };
        }
    }

    my $vars = {
        R        => \%R,
        branches => \@branches,
    };

    my $html = "$R{options}{outputdir}/$R{filenames}{$R{file}}--branch.html";
    $Template->process("branches", $vars, $html) or die $Template->error();
}

sub print_conditions {
    my $conditions = $R{db}->cover->file($R{file})->condition;
    return unless $conditions;

    my %r;
    for my $location (sort { $a <=> $b } $conditions->items) {
        my %count;
        for my $c (@{$conditions->location($location)}) {
            $count{$c->type}++;
            # print "-- [$count{$c->type}][@{[$c->text]}]}]\n";
            my $text = $c->text;
            ($text) = _highlight($text) if $Have_highlighter;

            push @{$r{$c->type}},
                {
                    number    => $count{$c->type} == 1 ? $location : "",
                    condition => $c,
                    parts     => [
                        map { text  => $c->value($_),
                              class => class($c->value($_), $c->error($_),
                                             "condition") },
                            0 .. $c->total - 1
                    ],
                    text      => $text,
                };
        }
    }

    my @types = map
                {
                    name       => do { my $n = $_; $n =~ s/_/ /g; $n },
                    headers    => [ map { encode_entities($_) }
                                    @{$r{$_}[0]{condition}->headers || []} ],
                    conditions => $r{$_},
                }, sort keys %r;

    my $vars = {
        R     => \%R,
        types => \@types,
    };

    # use Devel::Cover::Dumper; print Dumper \@types;

    my $html = "$R{options}{outputdir}/$R{filenames}{$R{file}}--condition.html";
    $Template->process("conditions", $vars, $html) or die $Template->error();
}

sub print_subroutines {
    my $subroutines = $R{db}->cover->file($R{file})->subroutine;
    return unless $subroutines;
    my $s = $R{options}{show}{subroutine};

    my $pods;
    $pods = $R{db}->cover->file($R{file})->pod if $R{options}{show}{pod};

    my $subs;
    for my $line (sort { $a <=> $b } $subroutines->items) {
        my @p;
        if ($pods) {
            my $l = $pods->location($line);
            @p = @$l if $l;
        }
        for my $o (@{$subroutines->location($line)}) {
            my $p = shift @p;
            push @$subs, {
                line   => $line,
                name   => $o->name,
                count  => $s ? $o->covered : "",
                class  => $s ? oclass($o, "subroutine") : "",
                pod    => $p ? $p->covered ? "Yes" : "No" : "n/a",
                pclass => $p ? oclass($p, "pod") : "",
            };
        }
    }

    my $vars = {
        R    => \%R,
        subs => $subs,
    };

    my $html =
        "$R{options}{outputdir}/$R{filenames}{$R{file}}--subroutine.html";
    $Template->process("subroutines", $vars, $html) or die $Template->error();
}

sub get_options {
    my ($self, $opt) = @_;
    $opt->{option}{outputfile} = "coverage.html";
    $opt->{option}{restrict}   = 1;
    $threshold->{$_} = $opt->{"report_$_"} for
        grep { defined $opt->{"report_$_"} } qw( c0 c1 c2 );
    die "Invalid command line options" unless
        GetOptions($opt->{option},
                   qw(
                       noppihtml
                       noperltidy
                       outputfile=s
                       restrict!
                     ));
}

sub report {
    my ($pkg, $db, $options) = @_;

    $Template = Template->new({
        LOAD_TEMPLATES => [
            Devel::Cover::Report::Html_basic::Template::Provider->new({}),
        ],
    });

    my $le = sub { ($_[0] >   0 ? "<" : "=") . " $_[0]" };
    my $ge = sub { ($_[0] < 100 ? ">" : "") . "= $_[0]" };

    my $fname = (sort keys %{$db->{runs}})[0] or return;
    my $run   = $db->{runs}{$fname};

    %R = (
        module  => { name => $run->name, version => $run->version },
        db      => $db,
        date    => do {
            my ($sec, $min, $hour, $mday, $mon, $year) = localtime;
            sprintf "%04d-%02d-%02d %02d:%02d:%02d",
                    $year + 1900, $mon + 1, $mday, $hour, $min, $sec
        },
        perl_v  => $] < 5.010 ? $] : $^V,
        os      => $^O,
        options => $options,
        version => $VERSION,
        showing => [ grep $options->{show}{$_}, $db->criteria ],
        headers => [
            map { ($db->criteria_short)[$_] }
                grep { $options->{show}{($db->criteria)[$_]} }
                     (0 .. $db->criteria - 1)
        ],
        annotations => [
            map { my $a = $_; map $a->header($_), 0 .. $a->count - 1 }
                @{$options->{annotations}}
        ],
        filenames => {
            map { $_ => do { (my $f = $_) =~ s/\W/-/g; $f } }
                @{$options->{file}}
        },
        exists      => { map { $_ => -e } @{$options->{file}} },
        get_summary => \&get_summary,
        c0          => $le->($options->{report_c0}),
        c1          => $le->($options->{report_c1}),
        c2          => $le->($options->{report_c2}),
        c3          => $ge->($options->{report_c2}),
    );

    write_file $R{options}{outputdir}, "all";

    for (@{$options->{file}}) {
        $R{file} = $_;
        $R{file_link} = "$R{filenames}{$_}.html";
        $R{file_html} = "$options->{outputdir}/$R{file_link}";
        my $show = $options->{show};
        print_file;
        print_branches    if $show->{branch};
        print_conditions  if $show->{condition};
        print_subroutines if $show->{subroutine} || $show->{pod};
    }

    my $html = print_summary;
    print "HTML output written to $html\n" unless $options->{silent};
}

1;

package Devel::Cover::Report::Html_basic::Template::Provider;

use strict;
use warnings;

# VERSION

use base "Template::Provider";

my %Templates;

sub fetch {
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
This file was generated by Devel::Cover Version [% R.version %]
Devel::Cover is copyright 2001-2024, Paul Johnson (paul@pjcj.net)
Devel::Cover is free. It is licensed under the same terms as Perl itself.
The latest version of Devel::Cover should be available from my homepage:
http://www.pjcj.net
-->
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"></meta>
    <meta http-equiv="Content-Language" content="en-us"></meta>
    <link rel="stylesheet" type="text/css" href="cover.css"></link>
    <script type="text/javascript" src="common.js"></script>
    <script type="text/javascript" src="css.js"></script>
    <script type="text/javascript" src="standardista-table-sorting.js"></script>
    <title> [% title || "Coverage Summary" %] </title>
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
        <td class="sh" align="right">Module</td>
        <td class="sv" align="left" colspan="4">[% R.module.name %]</td>
    </tr>
    <tr>
        <td class="sh" align="right">Version</td>
        <td class="sv" align="left" colspan="4">[% R.module.version %]</td>
    </tr>
    <tr>
        <td class="sh" align="right">Database:</td>
        <td class="sv" align="left" colspan="4">[% R.db.db %]</td>
    </tr>
    <tr>
        <td class="sh" align="right">Report date:</td>
        <td class="sv" align="left" colspan="4">[% R.date %]</td>
    </tr>
    <tr>
        <td class="sh" align="right">Perl version:</td>
        <td class="sv" align="left" colspan="4">[% R.perl_v %]</td>
    </tr>
    <tr>
        <td class="sh" align="right">OS:</td>
        <td class="sv" align="left" colspan="4">[% R.os %]</td>
    </tr>
    <tr>
        <td class="sh" align="right">Thresholds:</td>
        <td class="sv c0">[% R.c0 | html %]%</td>
        <td class="sv c1">[% R.c1 | html %]%</td>
        <td class="sv c2">[% R.c2 | html %]%</td>
        <td class="sv c3">[% R.c3 | html %]%</td>
    </tr>
</table>
<div><br /></div>

[% IF R.options.option.restrict %]
<script type="text/javascript">
<!-- hide
function filter_files(filter_by) {
    var allelements = document.getElementsByTagName("tr");
    var re_now      = new RegExp(filter_by, "i");
    for (var i = 0; i < allelements.length; i++) {
        if (allelements[i].className) {
            if (filter_by == "" || allelements[i].className == "Total" ||
                (filter_by.length && re_now.test(allelements[i].className))) {
                allelements[i].style.display = "table-row";
            } else if (filter_by.length &&
                       !re_now.test(allelements[i].className)) {
                allelements[i].style.display = "none";
            }
        }
    }
}
// -->
</script>

<form name="filterform"
      action='javascript:filter_files(document.forms["filterform"]["filterfield"].value)'>
    Restrict to regex:
    <input type="text" name="filterfield" /><input type="submit" />
</form>

<br />
[% END %]

<table class="sortable" id="coverage_table">
    <thead>
        <tr>
            <th> file </th>
            [% FOREACH header = R.headers %]
                <th> [% header %] </th>
            [% END %]
            <th> total </th>
        </tr>
    </thead>

    <tfoot>
    [% FOREACH file = files %]
        <tr align="center" valign="top" class="[% file %]">
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

        [% IF file == "Total" %]
            </tfoot>
            <tbody>
        [% END %]
    [% END %]
    </tbody>
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
            <td class="h">
                <a href="[% R.file_link %]#[% branch.number %]">[% branch.number %]</a>
            </td>
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
                <td class="h">
                    <a href="[% R.file_link %]#[% condition.number %]">[% condition.number %]</a>
                </td>
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
            <td class="h">
                <a href="[% R.file_link %]#[% sub.line %]">[% sub.line %]</a>
            </td>
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

Devel::Cover::Report::Html_basic - HTML backend for Devel::Cover

=head1 SYNOPSIS

 cover -report html_basic

=head1 DESCRIPTION

This module provides a HTML reporting mechanism for coverage data.  It
is designed to be called from the C<cover> program. It will add syntax
highlighting if C<PPI::HTML> or C<Perl::Tidy> is installed.

=head1 OPTIONS

The following command line options are supported:

 -outputfile  - name of output file              (default coverage.html)
 -restrict    - add restrict to regex form       (default on)
 -noppihtml   - disables PPI::HTML highlighting  (default off)
 -noperltidy  - disables Perl::Tidy highlighting (default off)

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2001-2024, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

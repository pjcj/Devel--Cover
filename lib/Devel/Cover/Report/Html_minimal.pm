package Devel::Cover::Report::Html_minimal;
BEGIN {require 5.006}
use strict;
use warnings;
use CGI;
use Getopt::Long;
use Devel::Cover::DB 0.36;
use Devel::Cover::Truth_Table 0.36;

our $VERSION = "0.36";

#-------------------------------------------------------------------------------
# Subroutine : get_coverage_for_line
# Purpose    : Retreive all available data for requested metrics on a line.
# Notes      : 
#-------------------------------------------------------------------------------
sub get_coverage_for_line {
    my ($options, $data, $line) = @_;
    my %coverage;
    foreach my $c (grep {$data->$_()} keys %{$options->{show}}) {
        my $m = $data->$c()->location($line);
        $coverage{$c} = $m if $m;
    }
    return \%coverage;
}


#-------------------------------------------------------------------------------
# Subroutine : get_summary_for_file
# Purpose    : 
# Notes      : 
#-------------------------------------------------------------------------------
sub get_summary_for_file {
    my $db   = shift;
    my $file = shift;
    my $show = shift;
    my %summary;

    my $data = $db->{summary}{$file};
    for my $c (@$show) {
        if (exists $data->{$c}) {
            $summary{$c} = {
                percent => sprintf("%4.1f", $data->{$c}{percentage}),
                ratio   => sprintf("%d / %d",
                    $data->{$c}{covered} || 0, $data->{$c}{total} || 0),
            };
        }
        else {
            $summary{$c} = {percent => 'n/a', ratio => undef};
        }
    }
    return \%summary;
}


#-------------------------------------------------------------------------------
# Subroutine : get_showing_headers
# Purpose    : 
# Notes      : 
#-------------------------------------------------------------------------------
sub get_showing_headers {
    my $db      = shift;
    my $options = shift;

    my @crit       = $db->criteria;
    my @short_crit = $db->criteria_short;
    my @showing    = grep $options->{show}{$_}, @crit;
    my @headers    = map  { $short_crit[$_] }
                     grep { $options->{show}{$crit[$_]} }
                     (0 .. $#crit);

    return(\@showing, \@headers);
}


#-------------------------------------------------------------------------------
# Subroutine : truth_table
# Purpose    : 
# Notes      : 
#-------------------------------------------------------------------------------
sub truth_table {
    return if @_ > 16;
    my @lops;
    foreach my $c (@_) {
        my $op = $c->[1]{type};
        my @hit = map {defined() && $_ > 0 ? 1 : 0} @{$c->[0]};
        @hit = reverse @hit if $op =~ /^or_[23]$/;
        my $t = {
            tt   => Devel::Cover::Truth_Table->new_primitive($op, @hit),
            cvg  => $c->[1],
            expr => join(' ', @{$c->[1]}{qw/left op right/}),
        };
        push(@lops, $t);
    }
    return map {[$_->{tt}->sort, $_->{expr}]} merge_lineops(@lops);
}

#-------------------------------------------------------------------------------
# Subroutine : merge_lineops()
# Purpose    : Merge multiple conditional expressions into composite
#              truth table(s).
# Notes      :
#-------------------------------------------------------------------------------
sub merge_lineops {
    my @ops = @_;
    my $rotations;
    while ($#ops > 0) {
        my $rm;
        for (1 .. $#ops) {
            if ($ops[0]{expr} eq $ops[$_]{cvg}{left}) {
                $ops[$_]{tt}->left_merge($ops[0]{tt});
                $ops[0] = $ops[$_];
                $rm = $_; last;
            }
            elsif ($ops[0]{expr} eq $ops[$_]{cvg}{right}) {
                $ops[$_]{tt}->right_merge($ops[0]{tt});
                $ops[0] = $ops[$_];
                $rm = $_; last;
            }
            elsif ($ops[$_]{expr} eq $ops[0]{cvg}{left}) {
                $ops[0]{tt}->left_merge($ops[$_]{tt});
                $rm = $_; last;
            }
            elsif ($ops[$_]{expr} eq $ops[0]{cvg}{right}) {
                $ops[0]{tt}->right_merge($ops[$_]{tt});
                $rm = $_; last;
            }
        }
        if ($rm) {
            splice(@ops, $rm, 1);
            $rotations = 0;
        }
        else {
            # First op didn't merge with anything. Rotate @ops in hopes
            # of finding something that can be merged.
            unshift(@ops, pop @ops);

            # Hmm... we've come full circle and *still* haven't found
            # anything to merge. Did the source code have multiple
            # statements on the same line?
            last if ($rotations++ > $#ops);
        }
    }
    return @ops;
}

#===============================================================================
my %Filenames;
my @class = qw'c0 c1 c2 c3';

#-------------------------------------------------------------------------------
# Subroutine : bclass()
# Purpose    : Determine the CSS class for an element based on boolean coverage.
# Notes      :
#-------------------------------------------------------------------------------
sub bclass {
    my @c = map {$_ ? $class[-1] : $class[0] } @_;
    return wantarray ? @c : $c[0];
}

#-------------------------------------------------------------------------------
# Subroutine : pclass()
# Purpose    : Determine the CSS class for an element based on percent covered
# Notes      :
#-------------------------------------------------------------------------------
sub pclass {
    my @c;
    foreach my $p (@_) {
        $p <  75 && do {push @c, $class[0]; next};
        $p <  90 && do {push @c, $class[1]; next};
        $p < 100 && do {push @c, $class[2]; next};
        push @c, $class[3];
    }
    return wantarray ? @c : $c[0];
}

#-------------------------------------------------------------------------------
# Subroutine : get_coverage_report
# Purpose    : 
# Notes      : 
#-------------------------------------------------------------------------------
sub get_coverage_report {
    my $type = shift;
    my $data = shift;
    return _branch_report($data)     if $type eq 'branch';
    return _condition_report($data)  if $type eq 'condition';
    return _time_report($data)       if $type eq 'time';
    return _count_report($type, $data);
}
#-------------------------------------------------------------------------------
sub _count_report {
    my $type = shift;
    my $data = shift;
    return map {{
        class      => bclass($_->covered),
        percentage => $_->covered,
    }} @{$data->{$type}}
}
#-------------------------------------------------------------------------------
sub _branch_report {
    my $coverage = shift;
    my $sfmt = qq'<table width="100%%"><tr><td class="%s">T</td><td class="%s">F</td></tr></table>';

    return map {{
        percentage => sprintf("%.0f", $_->percentage),
        title      => sprintf("%s/%s", $_->[0][0] ? 'T' : '-', $_->[0][1] ? 'F' : '-'),
        class      => pclass($_->percentage),
        string     => sprintf($sfmt, bclass($_->[0][0]), bclass($_->[0][1])),
    }} @{$coverage->{branch}}
}
#-------------------------------------------------------------------------------
sub _condition_report {
    my $coverage = shift;

    my @tables = truth_table(@{$coverage->{condition}});
    return unless @tables;
    return map {{
        percentage => sprintf("%.0f", $_->[0]->percentage),
        class      => pclass($_->[0]->percentage),
        string     => $_->[0]->html(bclass(0,1)),
    }} @tables;
}
#-------------------------------------------------------------------------------
sub _time_report {
    my $coverage = shift;
    return map {{string => $_->covered}} @{$coverage->{time}};
}
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Subroutine : print_stylesheet()
# Purpose    : Create the stylesheet for HTML reports.
# Notes      :
#-------------------------------------------------------------------------------
sub print_stylesheet {
    my ($db, $options) = @_;
    my $file = "$options->{outputdir}/cover.css";

    open(my $css, '>', $file) or return;
    my $p = tell(DATA);
    print $css <DATA>;
    seek(DATA, $p, 0);
    close($css);
}


#-------------------------------------------------------------------------------
# Subroutine : print_html_header
# Purpose    :
# Notes      :
#-------------------------------------------------------------------------------
sub print_html_header {
    my $fh    = shift;
    my $title = shift;

    print $fh <<"END_HTML";
<!--
This file was generated by Devel::Cover Version 0.36
Devel::Cover is copyright 2001-2004, Paul Johnson (pjcj\@cpan.org)
Devel::Cover is free. It is licensed under the same terms as Perl itself.
The latest version of Devel::Cover should be available from my homepage:
http://www.pjcj.net
-->

<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML Basic 1.0//EN"
    "http://www.w3.org/TR/xhtml-basic/xhtml-basic10.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1"></meta>
<meta http-equiv="Content-Language" content="en-us"></meta>
<link rel="stylesheet" type="text/css" href="cover.css"></link>
<title>$title</title>
</head>
END_HTML

}


#-------------------------------------------------------------------------------
# Subroutine : print_summary
# Purpose    : 
# Notes      : 
#-------------------------------------------------------------------------------
sub print_summary {
    my $fh       = shift;
    my $title    = shift;
    my $file     = shift;
    my $percent  = sprintf("%.1f", shift @_);
    my $class    = pclass($percent);
    my $perlver  = join('.', map {ord} split(//, $^V)); # should come from db
    my $platform = $^O;                                 # should come from db

    print $fh <<"END_HTML";
<body>
<h1>$title</h1>
<table>
<tr><td class="h" align="right">File:</td><td align="left">$file</td></tr>
<tr><td class="h" align="right">Coverage:</td><td align="left" class="$class">$percent\%</td></tr>
<tr><td class="h" align="right">Perl version:</td><td align="left">$perlver</td></tr>
<tr><td class="h" align="right">Platform:</td><td align="left">$platform</td></tr>
</table>
<div><br/></div>
<table>
END_HTML

}

#-------------------------------------------------------------------------------
# Subroutine : print_th
# Purpose    : 
# Notes      : 
#-------------------------------------------------------------------------------
sub print_th {
    my ($fh, $th, $span) = @_;
    print $fh '<tr>';
    foreach my $h (@$th) {
        print $fh $span->{$h} ? qq'<th colspan="$span->{$h}">$h</th>' : "<th>$h</th>";
    }
    print $fh "</tr>\n";
}


#-------------------------------------------------------------------------------
# Subroutine : get_link
# Purpose    : 
# Notes      : 
#-------------------------------------------------------------------------------
sub get_link {
    my $file = shift;
    my $type = shift;
    my $line = shift;
    return unless exists $Filenames{$file};
    my $link = $Filenames{$file};
    $link .= "--$type" if $type;
    $link .= ".html";
    $link .= "#L$line" if $line;
    return $link;
}


#-------------------------------------------------------------------------------
# Subroutine : print_summary_report()
# Purpose    : Print the database summary report.
# Notes      :
#-------------------------------------------------------------------------------
sub print_summary_report {
    my ($db, $options) = @_;

    my $outfile = "$options->{outputdir}/$options->{option}{outputfile}";

    print "Writing HTML output to $outfile ...\n" unless $options->{silent};

    open(my $fh, '>', $outfile)
        or warn("Unable to open file '$outfile' [$!]\n"), return;

    my ($show, $th) = get_showing_headers($db, $options);
    push @$show, 'total';

    print_html_header($fh, 'Coverage Summary');
    print $fh <<"END_HTML";
<body>
<h1>Coverage Summary</h1>
<table>
<tr><td class="h" align="right">Database:</td><td align="left">$db->{db}</td></tr>
</table>
<div><br/></div>
<table>
END_HTML
    print_th($fh, ['file', @$th, 'total']);

    my @files = (grep($db->{summary}{$_}, @{$options->{file}}), 'Total');

    for my $file (@files) {
        my $summary = get_summary_for_file($db, $file, $show);

        my $url = get_link($file);
        if ($url) {
            print $fh qq'<tr><td align="left"><a href="$url">$file</a></td>';
        }
        else {
            print $fh qq'<tr><td align="left">$file</td>';
        }

        for my $c (@$show) {
            my $pc = $summary->{$c}{percent};
            my ($class, $popup, $link);

            if ($pc eq 'n/a' || $c eq 'time') {
                $class = $popup = '';
            }
            else {
                $class = sprintf(qq' class="%s"', pclass($pc));
                $popup = sprintf(qq' title="%s"', $summary->{$c}{ratio});
                if ($c =~ /branch|condition|subroutine/) {
                    $link = get_link($file, $c);
                }
            }

            if ($link) {
                printf $fh qq'<td%s%s><a href="%s">%s</a></td>',
                    $class, $popup, $link, $pc;
            }
            else {
                printf $fh qq'<td%s%s>%s</td>', $class, $popup, $pc;
            }
        }
        print $fh "</tr>\n";
    }
    print $fh "</table>\n</body>\n</html>\n";
    close($fh) or warn "Unable to close '$outfile' [$!]";
}


#-------------------------------------------------------------------------------
# Subroutine : escape_HTML
# Purpose    : make source code web-safe
# Notes      : 
#-------------------------------------------------------------------------------
sub escape_HTML {
    my $text = shift;
    chomp $text;

    $text = CGI::escapeHTML($text);

    # IE doesn't honor "white-space: pre" CSS
    $text =~ s/^(\t+)/' ' x (8 * length $1)/se;
    $text =~ s/^(\s+)/'&nbsp;' x length $1/se;

    return $text;
}

#-------------------------------------------------------------------------------
# Subroutine : print_file_report()
# Purpose    : Print coverage overview report for a file.
# Notes      :
#-------------------------------------------------------------------------------
sub print_file_report {
    my ($db, $fin, $opt) = @_;

    my $fout = "$opt->{outputdir}/$Filenames{$fin}.html";
    open(my $in,  '<', $fin ) or warn("Can't read file '$fin' [$!]\n"), return;
    open(my $out, '>', $fout) or warn("Can't open file '$fout' [$!]\n"), return;

    my ($show, $th) = get_showing_headers($db, $opt);
    my $file_data   = $db->cover->file($fin);

    print_html_header($out, "File Coverage: $fin");
    print_summary($out, 'File Coverage', $fin, $db->{summary}{$fin}{total}{percentage});
    print_th($out, ['line', @$th, 'code']);

    while (my $sloc = <$in>) {

        # Process stuff after __END__ or __DATA__ tokens
        if ($sloc =~ /^__(END|DATA)__/) {
            if ($opt->{option}{data}) {
                # print all data in one cell
                my ($i, $n) = ($., scalar @$th);
                while (my $line = <$in>) { $sloc .= $line }
                $sloc = escape_HTML($sloc);
                print $out qq'<tr><td class="h">$i - $.</td><td colspan="$n"></td><td class="s"><pre>$sloc</pre></td></tr>\n';
                # &nbsp; is IE empty cell hack
                #print $out qq'<tr><td class="h">$i - $.</td><td colspan="$n">&nbsp;</td><td class="s"><pre>$sloc</pre></td></tr>\n';
            }
            last;
        }

        # Process embedded POD
        if ($sloc =~ /^=(pod|head|over|item|begin|for)/) {
            if ($opt->{option}{pod}) {
                # print all POD in one cell
                my ($i, $n) = ($., scalar @$th);
                while (my $line = <$in>) {
                    $sloc .= $line;
                    last if $line =~ /^=cut/;
                }
                $sloc = escape_HTML($sloc);
                print $out qq'<tr><td class="h">$i - $.</td><td colspan="$n"></td><td class="s"><pre>$sloc</pre></td></tr>\n';
                # &nbsp; is IE empty cell hack
                #print $out qq'<tr><td class="h">$i - $.</td><td colspan="$n">&nbsp;</td><td class="s"><pre>$sloc</pre></td></tr>\n';
            }
            else {
                1 while (<$in> !~ /^=cut/);
            }
            next;
        }

        if ($sloc =~ /^\s*$/) {
            if ($opt->{option}{pod}) {
                my $n = @$th + 1;
                print $out qq'<tr><td class="h">$.</td><td colspan="$n"></td></tr>';
                # &nbsp; is IE empty cell hack
                #print $out qq'<tr><td class="h">$.</td><td colspan="$n">&nbsp;</td></tr>';
            }
            next;
        }

        $sloc = escape_HTML($sloc);

        print $out qq'<tr><td class="h">$.</td>';

        my $metric = get_coverage_for_line($opt, $file_data, $.);

        foreach my $c (@$show) {
            my @m = get_coverage_report($c, $metric);
            print $out '<td>';
            foreach my $m (@m) {

                if ($opt->{option}{unified} &&
                    ($c eq 'branch' || $c eq 'condition')) {
                    print $out '<div>', $m->{string}, '</div>';
                }
                else {
                    my $link;
                    if ($c =~ /branch|condition|subroutine/) {
                        $link = get_link($fin, $c, $.);
                    }
    
                    my $text = '<div';
                    $text .= $m->{class} ? qq' class="$m->{class}"' : '';
                    $text .= $m->{title} ? qq' title="$m->{title}"' : '';
                    $text .= '>';
                    $text .= $link       ? qq'<a href="$link">'     : '';
                    $text .= $m->{class} ? $m->{percentage}         : $m->{string};
                    $text .= $link       ? '</a></div>'             : '</div>';
                    print $out $text;
                }
            }
            print $out '</td>';
            #print $out '&nbsp;' unless @m; # IE empty cell hack
        }
        print $out qq'<td class="s">$sloc</td></tr>\n';
    }
    print $out "</table>\n</body>\n</html>\n";

    close($in)  or warn "Can't close file '$fin' [$!]";
    close($out) or warn "Can't close file '$fout' [$!]";
}

#-------------------------------------------------------------------------------
# Subroutine : print_branch_report()
# Purpose    : Print branch coverage report for a file.
# Notes      :
#-------------------------------------------------------------------------------
sub print_branch_report {
    my ($db, $file, $opt) = @_;
    my $data = $db->cover->file($file)->branch;
    return unless $data;

    my $fout = "$opt->{outputdir}/$Filenames{$file}--branch.html";
    open(my $out, '>', $fout) or warn("Can't open file '$fout' [$!]\n"), return;

    print_html_header($out, "Branch Coverage: $file");
    print_summary($out, 'Branch Coverage', $file, $db->{summary}{$file}{branch}{percentage});
    print_th($out, ['line', '%', 'coverage', 'branch'], {coverage => 2});

    my $fmt = qq'<tr><td class="h">%s</td>'
            . qq'<td class="%s">%.0f</td>'
            . qq'<td class="%s">T</td>'
            . qq'<td class="%s">F</td>'
            . qq'<td class="s">%s</td></tr>\n';

    foreach my $line (sort { $a <=> $b } $data->items) {
        my $n = 0;
        foreach my $x (@{$data->location($line)}) {
            my @tf = $x->values;
            printf $out ($fmt,
                $n++ > 0 ? '' : qq'<a id="L$line">$line</a>',
                pclass($x->percentage), $x->percentage,
                bclass($tf[0]), bclass($tf[1]),
                escape_HTML($x->text),
            );
        }
    }
    print $out "</table>\n</body>\n</html>\n";
    close($out) or warn "Can't close file '$fout' [$!]";
}


#-------------------------------------------------------------------------------
# Subroutine : print_condition_report()
# Purpose    : Print condition coverage report for a file.
# Notes      :
#-------------------------------------------------------------------------------
sub print_condition_report {
    my ($db, $file, $opt) = @_;
    my $data = $db->cover->file($file)->condition;
    return unless $data;

    my $fout = "$opt->{outputdir}/$Filenames{$file}--condition.html";
    open(my $out, '>', $fout) or warn("Can't open file '$fout' [$!]\n"), return;

    print_html_header($out, "Condition Coverage: $file");
    print_summary($out, 'Condition Coverage', $file, $db->{summary}{$file}{condition}{percentage});
    print_th($out, ['line', '%', 'coverage', 'condition']);

    my $fmt = qq'<tr><td class="h">%s</td>'
            . qq'<td class="%s">%.0f</td>'
            . qq'<td>%s</td>'
            . qq'<td class="s">%s</td></tr>\n';

    foreach my $line (sort { $a <=> $b } $data->items) {
        my @tt = $data->truth_table($line);
        my $n = 0;
        foreach my $x (@tt) {
            printf $out ($fmt,
                $n++ > 0 ? '' : qq'<a id="L$line">$line</a>',
                pclass($x->[0]->percentage), $x->[0]->percentage,
                '<div>' . $x->[0]->html(bclass(0,1)) . '</div>',
                escape_HTML($x->[1]),
            );
        }
    }
    print $out "</table>\n</body>\n</html>\n";
    close($out) or warn "Can't close file '$fout' [$!]";
}


#-------------------------------------------------------------------------------
# Subroutine : print_sub_report
# Purpose    : 
# Notes      : 
#-------------------------------------------------------------------------------
sub print_sub_report {
    my ($db, $file, $opt) = @_;
    my $data = $db->cover->file($file)->subroutine;
    return unless $data;

    my $fout = "$opt->{outputdir}/$Filenames{$file}--subroutine.html";
    open(my $out, '>', $fout) or warn("Can't open file '$fout' [$!]\n"), return;

    print_html_header($out, "Subroutine Coverage: $file");
    print_summary($out, 'Subroutine Coverage', $file, $db->{summary}{$file}{subroutine}{percentage});
    print_th($out, ['line', 'subroutine']);

    my $fmt = qq'<tr><td class="h">%s</td>'
            . qq'<td class="%s"><div class="s">%s</div></td></tr>\n';

    foreach my $line (sort { $a <=> $b } $data->items) {
        my $l = $data->location($line);
        my $n = 0;
        foreach my $x (@$l) {
            printf $out ($fmt,
                $n++ > 0 ? '' : qq'<a id="L$line">$line</a>',
                pclass($x->percentage),
                escape_HTML($x->name),
            );
        }
    }
    print $out "</table>\n</body>\n</html>\n";
    close($out) or warn "Can't close file '$fout' [$!]";
}


sub get_options
{
    my ($self, $opt) = @_;
    $opt->{option}{pod}        = 1;
    $opt->{option}{outputfile} = "coverage.html";
    die "Bad option" unless
        GetOptions($opt->{option},
                   qw(
                       data!
                       outputfile=s
                       pod!
                       unified!
                     ));
}


#-------------------------------------------------------------------------------
# Subroutine : report()
# Purpose    : Entry point for printing HTML reports.
# Notes      :
#-------------------------------------------------------------------------------
sub report {
    my (undef, $db, $opt) = @_;

    my @files  = @{$opt->{file}};
    %Filenames = map {$_ => do {(my $f = $_) =~ s/\W/-/g; $f}} @files;

    print_stylesheet($db, $opt);
    print_summary_report($db, $opt);
    for my $file (@files) {
        print_file_report($db, $file, $opt);
        unless ($opt->{option}{unified}) {
            print_branch_report    ($db, $file, $opt) if $opt->{show}{branch};
            print_condition_report ($db, $file, $opt) if $opt->{show}{condition};
            print_sub_report       ($db, $file, $opt) if $opt->{show}{subroutine};
        }
    }

    print "done.\n" unless $opt->{silent};
}

=pod

=head1 NAME

Devel::Cover::Report::Html_minimal - Backend for HTML reporting of coverage
statistics

=head1 SYNOPSIS

 use Devel::Cover::Report::Html_minimal;

 Devel::Cover::Report::Html_minimal->report($db, $options);

=head1 DESCRIPTION

This module provides a HTML reporting mechanism for coverage data. It is
designed to be called from the C<cover> program.

Based on an original by Paul Johnson, the output was greatly improved by Michael
Carman (mjcarman@mchsi.com).

=head1 OPTIONS

Options are specified by adding the appropraite flags to the C<cover> program.
This report format supports the following:

=over 4

=item outputfile

Specifies the filename of the main output file.  The default is
F<coverage.html>.  Specify F<index.html> if you just want to publish the whole
directory.

=item pod

Includes POD (and blank lines) in the file report. This is on by default.  It
may be turned off with -nopod.

=item data

Includes text after the C<__DATA__> or C<__END__> tokens in the file report. By
default, this text is trimmed.

Note: If your POD is after an C<__END__>, you have to specify 'data' to include
it, not 'pod'. The 'pod' option only applies to POD before the C<__END__>.

=item unified

Generates a "unified" report for each file. The detailed data that normally
appears in the auxilliary reports (branch, condition, etc.) is placed in the
file report, and the auxilliarry reports are not generated.

=back

=head1 SEE ALSO

Devel::Cover

=head1 VERSION

Version 0.36 - 9th March 2004

=head1 LICENCE

Copyright 2001-2004, Paul Johnson (pjcj@cpan.org)

This software is free. It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

1;

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
	-moz-border-radius: 10px;
}

a {
	color: #000000;
}
a:visited {
	color: #333333;
}

table {
	border-spacing: 1px;
}
tr {
	text-align : center;
	vertical-align: top;
}
th,.h {
	background-color: #cccccc;
	border: solid 1px #333333;
	padding-left:  0.2em;
	padding-right: 0.2em;
}
td {
	border: solid 1px #cccccc;
}

/* source code */
pre,.s {
	text-align: left;
	font-family: monospace;
	white-space: pre;
	padding: 0em 0.5em 0em 0.5em;
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

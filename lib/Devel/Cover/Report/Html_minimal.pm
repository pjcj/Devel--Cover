package Devel::Cover::Report::Html_minimal;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use HTML::Entities            qw( encode_entities );
use Getopt::Long              qw( GetOptions );
use Devel::Cover::Html_Common qw( launch );          ## no perlimports
use Devel::Cover::Truth_Table ();

our $VERSION;

BEGIN {
  # VERSION
}

use Devel::Cover::Inc ();

BEGIN { $VERSION //= $Devel::Cover::Inc::VERSION }

# Retrieve all available data for requested metrics on a line
sub get_coverage_for_line ($options, $data, $line) {
  my $coverage = {};
  for my $c (grep { $data->$_ } keys $options->{show}->%*) {
    my $m = $data->$c->location($line);
    $coverage->{$c} = $m if $m;
  }
  $coverage
}

# Build a coverage summary for a single file
sub get_summary_for_file ($db, $file, $show) {
  my $summary = {};
  my $data    = $db->{summary}{$file};

  for my $c (@$show) {
    if (exists $data->{$c}) {
      $summary->{$c} = {
        percent => do {
          my $x = sprintf "%5.2f", $data->{$c}{percentage};
          chop $x;
          $x
        },
        ratio => sprintf("%d / %d",
          $data->{$c}{covered} || 0,
          $data->{$c}{total}   || 0,
        ),
        error => $data->{$c}{error},
      };
    } else {
      $summary->{$c} = { percent => "n/a", ratio => undef, error => undef };
    }
  }
  $summary
}

# Return the active coverage criteria and their short header names
sub get_showing_headers ($db, $options) {
  my @crit       = $db->criteria;
  my @short_crit = $db->criteria_short;
  my @showing    = grep $options->{show}{$_}, @crit;
  my @headers    = map { $short_crit[$_] }
    grep { $options->{show}{ $crit[$_] } } (0 .. $#crit);

  (\@showing, \@headers)
}

# Build truth tables from condition coverage data
sub truth_table (@args) {
  return if @args > 16;
  my @lops;
  my $n = 0;
  for my $c (@args) {
    my $op  = $c->[1]{type};
    my @hit = map { defined() && $_ > 0 ? 1 : 0 } $c->[0]->@*;
    @hit = reverse @hit if $op =~ /^or_[23]$/;
    my $t = {
      tt   => Devel::Cover::Truth_Table->new_primitive($op, @hit),
      cvg  => $c->[1],
      expr => join " ",
      $c->[1]->@{ qw( left op right ) },
    };
    push @lops, $t;
  } map { [ $_->{tt}->sort, $_->{expr} ] } merge_lineops(@lops)
}

# Merge multiple conditional expressions into composite truth tables
sub merge_lineops (@ops) {
  my $rotations;
  while ($#ops > 0) {
    my $rm;
    for (1 .. $#ops) {
      if ($ops[0]{expr} eq $ops[$_]{cvg}{left}) {
        $ops[$_]{tt}->left_merge($ops[0]{tt});
        $ops[0] = $ops[$_];
        $rm = $_;
        last;
      } elsif ($ops[0]{expr} eq $ops[$_]{cvg}{right}) {
        $ops[$_]{tt}->right_merge($ops[0]{tt});
        $ops[0] = $ops[$_];
        $rm = $_;
        last;
      } elsif ($ops[$_]{expr} eq $ops[0]{cvg}{left}) {
        $ops[0]{tt}->left_merge($ops[$_]{tt});
        $rm = $_;
        last;
      } elsif ($ops[$_]{expr} eq $ops[0]{cvg}{right}) {
        $ops[0]{tt}->right_merge($ops[$_]{tt});
        $rm = $_;
        last;
      }
    }
    if ($rm) {
      splice @ops, $rm, 1;
      $rotations = 0;
    } else {
      # First op didn't merge with anything. Rotate @ops in hopes of finding
      # something that can be merged.
      unshift @ops, pop @ops;

      # Hmm... we've come full circle and *still* haven't found anything to
      # merge. Did the source code have multiple statements on the same line?
      last if ($rotations++ > $#ops);
    }
  }
  @ops
}

my %Filenames;
my @Class     = qw( c0 c1 c2 c3 );
my $Threshold = { c0 => 75, c1 => 90, c2 => 100 };

# Determine the CSS class based on boolean coverage
sub bclass (@vals) {
  my @c = map { $_ ? $Class[-1] : $Class[0] } @vals;
  wantarray ? @c : $c[0]
}

# Determine the CSS class based on percent covered
sub pclass ($p, $e) {
  return $Class[3] unless $e;
  $p < $Threshold->{c0} && return $Class[0];
  $p < $Threshold->{c1} && return $Class[1];
  $p < $Threshold->{c2} && return $Class[2];
  $Class[3]
}

# Dispatch to the appropriate coverage report renderer
sub get_coverage_report ($type, $data) {
  return _branch_report($data)    if $type eq "branch";
  return _condition_report($data) if $type eq "condition";
  return _time_report($data)      if $type eq "time";
  _count_report($type, $data)
}

sub _count_report ($type, $data) {
  map { {
    class      => bclass(!$_->error || $_->covered),
    percentage => $_->covered,
  } }
    $data->{$type}->@*
}

sub _branch_report ($coverage) {
  my $sfmt
    = '<table width="100%%"><tr>'
    . '<td class="%s">T</td>'
    . '<td class="%s">F</td>'
    . "</tr></table>";

  map { {
    percentage => sprintf("%.0f", $_->percentage),
    title  => sprintf("%s/%s", $_->[0][0] ? "T" : "-", $_->[0][1] ? "F" : "-"),
    class  => pclass($_->percentage, $_->error),
    string => sprintf($sfmt, bclass($_->[0][0]), bclass($_->[0][1])),
  } } $coverage->{branch}->@*
}

sub _condition_report ($coverage) {
  # use Devel::Cover::Dumper; print STDERR Dumper $coverage;

  my @tables = truth_table($coverage->{condition}->@*);
  return unless @tables;
  map { {
    percentage => sprintf("%.0f", $_->[0]->percentage),
    class      => pclass($_->[0]->percentage, $_->[0]->error),
    string     => $_->[0]->html(bclass(0, 1)),
  } } @tables
}

sub _time_report ($coverage) {
  map { { string => $_->covered } } $coverage->{time}->@*
}

# Create the stylesheet for HTML reports
sub print_stylesheet ($db, $options) {
  my $file = "$options->{outputdir}/cover.css";

  open my $css, ">", $file or return;
  my $p = tell DATA;
  print $css <DATA>;
  seek DATA, $p, 0;
  close $css or warn "Can't close '$file' [$!]";
}

# Print the HTML document header
sub print_html_header ($fh, $title) {
  print $fh <<"END_HTML";
<!DOCTYPE html
     PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
     "https://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="https://www.w3.org/1999/xhtml">
<!--
This file was generated by Devel::Cover Version $VERSION
Devel::Cover is copyright 2001-2026, Paul Johnson (paul\@pjcj.net)
Devel::Cover is free. It is licensed under the same terms as Perl itself.
The latest version of Devel::Cover should be available from my homepage:
https://pjcj.net
-->
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"></meta>
    <meta http-equiv="Content-Language" content="en-us"></meta>
    <link rel="stylesheet" type="text/css" href="cover.css"></link>
    <link rel="stylesheet" type="text/css" href="cover.css"></link>
    <title>$title</title>
</head>
END_HTML

}

# Print the file summary header with coverage percentage
sub print_summary ($fh, $title, $file, $raw_pct, $err, $db) {
  my $percent = sprintf "%.1f", $raw_pct || 0;
  my $class   = pclass($percent, $err);

  print $fh <<"END_HTML";
<body>
<h1>$title</h1>
<table>
<tr><td class="h" align="right">File:</td>
<td align="left">$file</td></tr>
<tr><td class="h" align="right">Coverage:</td>
<td align="left" class="$class">$percent\%</td></tr>
</table>
<div><br/></div>
<table>
END_HTML

}

# Print a table header row
sub print_th ($fh, $th, $span = undef) {
  print $fh "<tr>";
  for my $h (@$th) {
    print $fh $span
      && $span->{$h} ? qq(<th colspan="$span->{$h}">$h</th>) : "<th>$h</th>";
  }
  print $fh "</tr>\n";
}

# Build a link to a coverage report page
sub get_link ($file, $type = undef, $line = undef) {
  return unless exists $Filenames{$file};
  my $link = $Filenames{$file};
  $link .= "--$type" if $type;
  $link .= ".html";
  $link .= "#L$line" if $line;
  $link
}

# Make source code web-safe
sub escape_HTML ($text) {  ## no critic (NamingConventions::Capitalization)
  chomp $text;

  $text = encode_entities($text);

  # Do not allow FF in text
  $text =~ tr/\x0c//d;

  # IE doesn't honor "white-space: pre" CSS
  my @text = split m/\n/ => $text;
  for (@text) {
    # Expand all tabs to spaces
    1 while s/\t+/' ' x (length($&) * 8 - length($`) % 8)/e;
    # make multiple spaces be multiple spaces
    s/(  +)/'&nbsp;' x length $1/ge;
  }

  join "\n" => @text
}

# Render coverage metric cells for a single source line
sub _render_coverage_cells ($out, $fin, $opt, $show, $metric) {
  for my $c (@$show) {
    my @m = get_coverage_report($c, $metric);
    print $out "<td>";
    for my $m (@m) {

      if ($opt->{option}{unified} && ($c eq "branch" || $c eq "condition")) {
        print $out "<div>", $m->{string}, "</div>";
      } else {
        my $link;
        if ($c =~ /^(?:branch|condition|subroutine)$/) {
          $link = get_link($fin, $c, $.);
        }

        no warnings "uninitialized";
        my $text = "<div";
        $text .= $m->{class} ? qq( class="$m->{class}") : "";
        $text .= $m->{title} ? qq( title="$m->{title}") : "";
        $text .= ">";
        $text .= $link       ? qq(<a href="$link">) : "";
        $text .= $m->{class} ? $m->{percentage}     : $m->{string};
        $text .= $link       ? "</a></div>"         : "</div>";
        print $out $text;
      }
    }
    print $out "</td>";
  }
}

# Print coverage overview report for a file
sub print_file_report ($db, $fin, $opt) {
  my $fout = "$opt->{outputdir}/$Filenames{$fin}.html";
  open my $in,  "<", $fin  or warn("Can't read file '$fin' [$!]\n"),  return;
  open my $out, ">", $fout or warn("Can't open file '$fout' [$!]\n"), return;

  my ($show, $th) = get_showing_headers($db, $opt);
  my $file_data = $db->cover->file($fin);

  print_html_header($out, "File Coverage: $fin");
  print_summary(
    $out, "File Coverage",
    $fin,
    $db->{summary}{$fin}{total}{percentage},
    $db->{summary}{$fin}{total}{error}, $db,
  );
  print_th($out, [ "line", @$th, "code" ]);

  my $autoloader = 0;
  while (my $sloc = <$in>) {
    $autoloader ||= $sloc =~ /use\s+AutoLoader/;

    # Process stuff after __END__ or __DATA__ tokens
    if (!$autoloader && $sloc =~ /^__(END|DATA)__/) {
      if ($opt->{option}{data}) {
        # print all data in one cell
        my ($i, $n) = ($., scalar @$th);
        while (my $line = <$in>) { $sloc .= $line }
        $sloc = escape_HTML($sloc);
        print $out qq(<tr><td class="h">$i - $.</td>)
          . qq(<td colspan="$n"></td>)
          . qq(<td class="s"><pre>$sloc</pre>)
          . qq(</td></tr>\n);
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
        print $out qq(<tr><td class="h">$i - $.</td>)
          . qq(<td colspan="$n"></td>)
          . qq(<td class="s"><pre>$sloc</pre>)
          . qq(</td></tr>\n);
      } else {
        1 while (<$in> !~ /^=cut/);
      }
      next;
    }

    if ($sloc =~ /^\s*$/) {
      if ($opt->{option}{pod}) {
        my $n = @$th + 1;
        print $out qq(<tr><td class="h">$.</td>)
          . qq(<td colspan="$n"></td></tr>);
      }
      next;
    }

    $sloc = escape_HTML($sloc);

    print $out qq(<tr><td class="h">$.</td>);

    my $metric = get_coverage_for_line($opt, $file_data, $.);

    _render_coverage_cells($out, $fin, $opt, $show, $metric);
    print $out qq(<td class="s">$sloc</td></tr>\n);
  }
  print $out "</table>\n</body>\n</html>\n";

  close $in  or warn "Can't close file '$fin' [$!]";
  close $out or warn "Can't close file '$fout' [$!]";
}

# Print branch coverage report for a file
sub print_branch_report ($db, $file, $opt) {
  my $data = $db->cover->file($file)->branch;
  return unless $data;

  my $fout = "$opt->{outputdir}/$Filenames{$file}--branch.html";
  open my $out, ">", $fout or warn("Can't open file '$fout' [$!]\n"), return;

  print_html_header($out, "Branch Coverage: $file");
  print_summary(
    $out, "Branch Coverage",
    $file,
    $db->{summary}{$file}{branch}{percentage},
    $db->{summary}{$file}{branch}{error}, $db,
  );
  print_th($out, [ "line", "%", "coverage", "branch" ], { coverage => 2 });

  my $fmt
    = '<tr><td class="h">%s</td>'
    . '<td class="%s">%.0f</td>'
    . '<td class="%s">T</td>'
    . '<td class="%s">F</td>'
    . qq(<td class="s">%s</td></tr>\n);

  for my $line (sort { $a <=> $b } $data->items) {
    my $n = 0;
    for my $x ($data->location($line)->@*) {
      my @tf = $x->values;
      printf $out $fmt, $n++ > 0 ? "" : qq(<a id="L$line">$line</a>),
        pclass($x->percentage, $x->error), $x->percentage, bclass($tf[0]),
        bclass($tf[1]), escape_HTML($x->text);
    }
  }
  print $out "</table>\n</body>\n</html>\n";
  close $out or warn "Can't close file '$fout' [$!]";
}

# Print condition coverage report for a file
sub print_condition_report ($db, $file, $opt) {
  my $data = $db->cover->file($file)->condition;
  return unless $data;

  my $fout = "$opt->{outputdir}/$Filenames{$file}--condition.html";
  open my $out, ">", $fout or warn("Can't open file '$fout' [$!]\n"), return;

  print_html_header($out, "Condition Coverage: $file");
  print_summary(
    $out, "Condition Coverage",
    $file,
    $db->{summary}{$file}{condition}{percentage},
    $db->{summary}{$file}{condition}{error}, $db,
  );
  print_th($out, [ "line", "%", "coverage", "condition" ]);

  my $fmt
    = '<tr><td class="h">%s</td>'
    . '<td class="%s">%.0f</td>'
    . "<td>%s</td>"
    . qq(<td class="s">%s</td></tr>\n);

  for my $line (sort { $a <=> $b } $data->items) {
    my @tt = $data->truth_table($line);
    my $n  = 0;
    for my $x (@tt) {
      printf $out $fmt, $n++ > 0 ? "" : qq(<a id="L$line">$line</a>),
        pclass($x->[0]->percentage, $x->[0]->error), $x->[0]->percentage,
        "<div>" . $x->[0]->html(bclass(0, 1)) . "</div>", escape_HTML($x->[1]);
    }
  }
  print $out "</table>\n</body>\n</html>\n";
  close $out or warn "Can't close file '$fout' [$!]";
}

# Print subroutine coverage report for a file
sub print_sub_report ($db, $file, $opt) {
  my $data = $db->cover->file($file)->subroutine;
  return unless $data;

  my $fout = "$opt->{outputdir}/$Filenames{$file}--subroutine.html";
  open my $out, ">", $fout or warn("Can't open file '$fout' [$!]\n"), return;

  print_html_header($out, "Subroutine Coverage: $file");
  print_summary(
    $out, "Subroutine Coverage",
    $file,
    $db->{summary}{$file}{subroutine}{percentage},
    $db->{summary}{$file}{subroutine}{error}, $db,
  );
  print_th($out, [ "line", "subroutine" ]);

  my $fmt
    = '<tr><td class="h">%s</td>'
    . '<td class="%s">'
    . '<div class="s">%s</div>'
    . "</td></tr>\n";

  for my $line (sort { $a <=> $b } $data->items) {
    my $l = $data->location($line);
    my $n = 0;
    for my $x (@$l) {
      printf $out $fmt, $n++ > 0 ? "" : qq(<a id="L$line">$line</a>),
        pclass($x->percentage, $x->error), escape_HTML($x->name);
    }
  }
  print $out "</table>\n</body>\n</html>\n";
  close $out or warn "Can't close file '$fout' [$!]";
}

# Print the database summary report
sub print_summary_report ($db, $options) {
  my $outfile = "$options->{outputdir}/$options->{option}{outputfile}";

  open my $fh, ">", $outfile
    or warn("Unable to open file '$outfile' [$!]\n"), return;

  my ($show, $th) = get_showing_headers($db, $options);
  push @$show, "total";

  my $le = sub ($v) {
    ($v > 0 ? "&lt;" : "=") . " $v%"
  };
  my $ge = sub ($v) {
    ($v < 100 ? "&gt;" : "") . "= $v%"
  };
  my @c = (
    $le->($options->{report_c0}), $le->($options->{report_c1}),
    $le->($options->{report_c2}), $ge->($options->{report_c2}),
  );
  my $date = do {
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime;
    sprintf "%04d-%02d-%02d %02d:%02d:%02d", $year + 1900, $mon + 1, $mday,
      $hour, $min, $sec
  };
  my $perl_v = $^V;
  my $os     = $^O;

  print_html_header($fh, $options->{option}{summarytitle});
  # TODO - >= 100% doesn't look nice.  See also Html_basic.
  print $fh <<"END_HTML";
<body>
<h1>$options->{option}{summarytitle}</h1>
<table>
  <tr><td class="h" align="right">Database:</td>
  <td align="left" colspan="4">$db->{db}</td></tr>
  <tr><td class="h" align="right">Report Date:</td>
  <td align="left" colspan="4">$date</td></tr>
  <tr><td class="h" align="right">Perl Version:</td>
  <td align="left" colspan="4">$perl_v</td></tr>
  <tr><td class="h" align="right">OS:</td>
  <td align="left" colspan="4">$os</td></tr>
  <tr>
    <td class="h" align="right">Thresholds:</td>
    <td class="c0">$c[0]</td>
    <td class="c1">$c[1]</td>
    <td class="c2">$c[2]</td>
    <td class="c3">$c[3]</td>
  </tr>
</table>
<div><br/></div>
<table>
END_HTML
  print_th($fh, [ "file", @$th, "total" ]);

  my @files = (grep($db->{summary}{$_}, $options->{file}->@*), "Total");

  for my $file (@files) {
    my $uncompiled
      = $file ne "Total" && $db->cover->file($file)->{meta}{uncompiled};
    my $summary = get_summary_for_file($db, $file, $show);

    my $url = get_link($file);
    if ($url) {
      print $fh '<tr><td align="left">' . qq(<a href="$url">$file</a>);
    } else {
      print $fh qq(<tr><td align="left">$file);
    }
    print $fh " <em>(untested)</em>" if $uncompiled;
    print $fh "</td>";

    for my $c (@$show) {
      my $pc = $summary->{$c}{percent};
      my ($class, $popup, $link);

      if ($pc eq "n/a" || $c eq "time") {
        $class = $popup = "";
      } else {
        $class = sprintf ' class="%s"', pclass($pc, $summary->{$c}{error});
        $popup = sprintf ' title="%s"', $c . ": " . $summary->{$c}{ratio};
        if (!$uncompiled && $c =~ /^(?:branch|condition|subroutine)$/) {
          $link = get_link($file, $c);
        }
      }

      if ($link) {
        printf $fh "<td%s%s>" . '<a href="%s">%s</a></td>', $class, $popup,
          $link, $pc;
      } else {
        printf $fh "<td%s%s>%s</td>", $class, $popup, $pc;
      }
    }
    print $fh "</tr>\n";
  }
  print $fh "</table>\n</body>\n</html>\n";
  close $fh or warn "Unable to close '$outfile' [$!]";

  print "HTML output written to $outfile\n" unless $options->{silent};
}

sub get_options ($self, $opt) {
  $opt->{option}{pod}          = 1;
  $opt->{option}{outputfile}   = "coverage.html";
  $opt->{option}{summarytitle} = "Coverage Summary";
  $Threshold->{$_}             = $opt->{"report_$_"}
    for grep { defined $opt->{"report_$_"} } qw( c0 c1 c2 );
  die "Invalid command line options"
    unless GetOptions(
      $opt->{option},
      qw(
        data!    outputfile=s pod!        summarytitle=s
        unified! report_c0=s  report_c1=s report_c2=s
      ),
    );
}

# Entry point for printing HTML reports
sub report ($pkg, $db, $opt) {
  my @files = $opt->{file}->@*;
  %Filenames = map {
    $_ => do { (my $f = $_) =~ s/\W/-/g; $f }
  } @files;

  print_stylesheet($db, $opt);
  for my $file (@files) {
    print_file_report($db, $file, $opt);
    unless (
         $db->cover->file($file)->{meta}{uncompiled}
      || $opt->{option}{unified}
    ) {
      print_branch_report($db, $file, $opt)    if $opt->{show}{branch};
      print_condition_report($db, $file, $opt) if $opt->{show}{condition};
      print_sub_report($db, $file, $opt)       if $opt->{show}{subroutine};
    }
  }
  print_summary_report($db, $opt);

  print "done.\n" unless $opt->{silent};
}

## no critic (Documentation::RequirePodAtEnd)

=pod

=encoding utf8

=head1 NAME

Devel::Cover::Report::Html_minimal - HTML backend for Devel::Cover

=head1 SYNOPSIS

 cover -report html_minimal

=head1 DESCRIPTION

This module provides a HTML reporting mechanism for coverage data. It is
designed to be called from the C<cover> program.

Based on an original by Paul Johnson, the output was greatly improved by Michael
Carman (mjcarman@mchsi.com).

=head1 OPTIONS

Options are specified by adding the appropriate flags to the C<cover> program.
This report format supports the following:

=over 4

=item outputfile

Specifies the filename of the main output file.  The default is
F<coverage.html>.  Specify F<index.html> if you just want to publish the whole
directory.

=item pod

Includes POD (and blank lines) in the file report.  This is on by default.  It
may be turned off with -nopod.

=item data

Includes text after the C<__DATA__> or C<__END__> tokens in the file report.  By
default, this text is trimmed.

Note: If your POD is after an C<__END__>, you have to specify 'data' to include
it, not 'pod'.  The 'pod' option only applies to POD before the C<__END__>.

=item unified

Generates a "unified" report for each file.  The detailed data that normally
appears in the auxiliary reports (branch, condition, etc.) are placed in the
file report, and the auxiliary reports are not generated.

=item summarytitle

Specify the title of the summary.  The default is "Coverage Summary".

=back

=head1 SEE ALSO

Devel::Cover

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free. It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

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
    border-collapse: collapse;
	border-spacing: 0px;
}
tr {
	text-align : center;
	vertical-align: top;
}
th,.h {
	background-color: #cccccc;
	border: solid 1px #333333;
    padding: 0em 0.2em;
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
.c0, .c1, .c2, .c3 { text-align: right; }
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

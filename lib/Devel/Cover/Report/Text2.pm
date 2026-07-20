package Devel::Cover::Report::Text2;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use List::Util              qw( max );
use Devel::Cover::Criterion ();
use Devel::Cover::Truth_Table;
use Devel::Cover::Path qw( common_prefix );

my %Format = (
  line       => "%4s ",
  err        => "%3s ",
  statement  => "%4s ",
  branch     => "%-6s ",
  condition  => "%-24s ",
  mcdc       => "%6s ",
  subroutine => "%4s ",
  pod        => "%4s ",
  time       => "%6s ",
  code       => "| %s\n",
);

sub headers ($db, $options) {
  my ($fmt, @data);

  for (qw( line err )) {
    $fmt .= $Format{$_};
    push @data, $_;
  }

  my %cr;
  @cr{ $db->criteria } = $db->criteria_short;
  for my $c ($db->criteria) {
    next unless $options->{show}{$c};
    $fmt .= $Format{$c};
    push @data, $cr{$c};
  }
  $fmt .= $Format{code};
  push @data, "code";

  ($fmt, @data)
}

sub get_metrics ($db, $options, $file_data, $line) {
  my %m;

  for my $c ($db->criteria) {
    next unless $options->{show}{$c};
    my $criterion = $file_data->$c;
    if ($criterion) {
      my $li = $criterion->location($line);
      $m{$c} = $li ? [@$li] : undef;
    }
  }
  %m
}

sub print_file ($db, $file, $options, $short) {
  open my $fh, "<", $file or warn "Unable to open '$file' [$!]\n" and return;

  my $display = $short->{$file};
  my $pct     = sprintf "%.1f%%", $db->{summary}{$file}{total}{percentage};
  my $pver    = $^V->stringify;
  print <<EOT;
#         File: $display
#     Coverage: $pct
# Perl Version: $pver
#     Platform: $^O

EOT

  my ($fmt, @hdr) = headers($db, $options);
  printf $fmt, @hdr;

  my $file_data = $db->cover->file($file);
  while (my $line = <$fh>) {
    chomp $line;

    my $error;
    my %metric = get_metrics($db, $options, $file_data, $.);
    my @row    = ([$.], [""]);

    for my $c ($db->criteria) {
      next unless $options->{show}{$c};
      push(@row, []), next unless $metric{$c};

      my $value = [];
      if ($c eq "branch") {
        @$value   = $file_data->branch->branch_coverage($.);
        $error  ||= $file_data->branch->error($.);
      } elsif ($c eq "condition") {
        @$value   = map $_->[0]->text, $file_data->condition->truth_table($.);
        $error  ||= $file_data->condition->error($.);
      } else {
        my $mode = Devel::Cover::Criterion->criterion_class($c)->display_mode;
        for my $o ($metric{$c}->@*) {
          push @$value, $mode eq "count" ? $o->covered : $o->percentage;
          $error ||= $o->error;
        }
      }
      push @row, $value;
    }

    $row[1] = ["***"] if $error;
    push @row, [$line];

    for my $i (0 .. max(map $#$_, @row)) {
      no warnings "uninitialized";
      printf $fmt, map $_->[$i], @row;
    }

    last if $line =~ /^__(END|DATA)__/;
  }
  close $fh or die "Unable to close '$file' [$!]";
  print "\n\n";
}

sub report ($pkg, $db, $options) {
  my @files = $options->{file}->@*;
  my ($prefix, $short) = common_prefix(@files);
  for my $file (@files) {
    next if $db->cover->file($file)->{meta}{uncompiled};
    print_file($db, $file, $options, $short);
  }
}

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Report::Text2 - Text backend for Devel::Cover

=head1 SYNOPSIS

 cover -report text2

=head1 DESCRIPTION

This module provides a textual reporting mechanism for coverage data. It is
designed to be called from the C<cover> program.

Unlike L<Devel::Cover::Report::Text>, which produces a per-file summary followed
by separate detail tables for each criterion, this reporter prints the source
file itself with per-line coverage columns prepended to every line.  The columns
are configurable per criterion via the C<%Format> hash inside this module.

Use C<text2> when you want to read the source while seeing coverage data inline
against each line - useful for auditing a specific file or stepping through it
by hand.  Use C<text> when you want aggregated tables: scan which files are
weakest, then drill into the per-criterion detail blocks (Branch, Condition,
MC/DC, Subroutines) for the missing pieces.

=head1 SEE ALSO

 Devel::Cover
 Devel::Cover::Report::Text

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

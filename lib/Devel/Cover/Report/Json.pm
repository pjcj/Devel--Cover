package Devel::Cover::Report::Json;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use Devel::Cover::DB::IO::JSON ();
use Devel::Cover::Inc          ();
use Devel::Cover::Log          qw( dcinfo );
use Getopt::Long               qw( GetOptions );

sub _runs ($db) {
  my @runs;
  for my $r (sort { $a->{start} <=> $b->{start} } $db->runs) {
    push @runs,
      { map { $_ => $r->$_ }
        qw( run perl OS dir name version abstract start finish ) };
  }
  \@runs
}

sub _meta ($f) {
  my $meta = $f->{meta} // {};
  +{
    uncompiled => $meta->{uncompiled} ? 1 : 0,
    digest     => $meta->{digest} // "",
    counts     => $meta->{counts} // {},
  }
}

sub _statements ($f) {
  my $criterion = $f->statement or return undef;
  my %out;
  for my $line ($criterion->items) {
    my @entries;
    for my $s ($criterion->location($line)->@*) {
      push @entries, {
          covered     => $s->covered + 0,
          uncoverable => $s->uncoverable ? 1 : 0,
          error       => $s->error       ? 1 : 0,
        };
    }
    $out{$line} = \@entries;
  }
  \%out
}

sub _branches ($f) {
  my $criterion = $f->branch or return undef;
  my %out;
  for my $line (sort { $a <=> $b } $criterion->items) {
    my @entries;
    for my $b ($criterion->location($line)->@*) {
      push @entries, {
          text        => $b->text,
          covered     => [map { $b->covered($_) + 0 } 0 .. $b->total - 1],
          uncoverable =>
          [map { $b->uncoverable($_) ? 1 : 0 } 0 .. $b->total - 1],
          error => $b->error ? 1 : 0,
        };
    }
    $out{$line} = \@entries;
  }
  \%out
}

sub _conditions ($f) {
  my $criterion = $f->condition or return undef;
  my %out;
  for my $line (sort { $a <=> $b } $criterion->items) {
    my @entries;
    for my $c ($criterion->location($line)->@*) {
      push @entries, {
          type        => $c->type,
          text        => $c->text,
          headers     => $c->headers,
          covered     => [map { $c->covered($_) + 0 } 0 .. $c->total - 1],
          uncoverable =>
          [map { $c->uncoverable($_) ? 1 : 0 } 0 .. $c->total - 1],
          error => $c->error ? 1 : 0,
        };
    }
    $out{$line} = \@entries;
  }
  \%out
}

sub _condition_truth_tables ($f) {
  my $criterion = $f->condition or return undef;
  my %out;
  for my $line (sort { $a <=> $b } $criterion->items) {
    my @tables = $criterion->truth_table($line);
    next unless @tables;
    $out{$line} = [
      map {
        my ($tt, $expr) = $_->@*;
        +{
          expr       => $expr,
          percentage => $tt->percentage + 0,
          rows       => [
            map +{
              inputs  => [$_->inputs],
              result  => $_->result + 0,
              covered => $_->covered ? 1 : 0,
            },
            @$tt,
          ],
        };
      } @tables
    ];
  }
  \%out
}

sub _subroutines ($f) {
  my $criterion = $f->subroutine or return undef;
  my %out;
  for my $line ($criterion->items) {
    my @entries;
    for my $s ($criterion->location($line)->@*) {
      push @entries, {
          name        => $s->name,
          covered     => $s->covered + 0,
          uncoverable => $s->uncoverable ? 1 : 0,
          error       => $s->error       ? 1 : 0,
        };
    }
    $out{$line} = \@entries;
  }
  \%out
}

sub _pod ($f) {
  my $criterion = $f->pod or return undef;
  my %out;
  for my $line ($criterion->items) {
    my @entries;
    for my $p ($criterion->location($line)->@*) {
      push @entries, {
          covered     => $p->covered + 0,
          uncoverable => $p->uncoverable ? 1 : 0,
          error       => $p->error       ? 1 : 0,
        };
    }
    $out{$line} = \@entries;
  }
  \%out
}

sub _time ($f) {
  my $criterion = $f->time or return undef;
  my %out;
  for my $line ($criterion->items) {
    $out{$line}
      = [map +{ value => $_->covered + 0 }, $criterion->location($line)->@*];
  }
  \%out
}

sub get_options ($self, $opt) {
  $opt->{option}{outputfile} = "cover.json";
  die "Invalid command line options"
    unless GetOptions($opt->{option}, qw( outputfile=s ));
}

sub report ($pkg, $db, $options) {
  my %sum_options = map { $_ => 1 } grep !/path|time/, $db->all_criteria,
    "force";
  $db->calculate_summary(%sum_options);

  my %files;
  for my $file ($options->{file}->@*) {
    my $f     = $db->cover->file($file);
    my $entry = { meta => _meta($f) };
    if (!$f->{meta}{uncompiled}) {
      $entry->{statements} = _statements($f) if $options->{show}{statement};
      $entry->{branches}   = _branches($f)   if $options->{show}{branch};
      $entry->{conditions} = _conditions($f) if $options->{show}{condition};
      $entry->{condition_truth_tables} = _condition_truth_tables($f)
        if $options->{show}{condition};
      $entry->{subroutines} = _subroutines($f) if $options->{show}{subroutine};
      $entry->{pod}         = _pod($f)         if $options->{show}{pod};
      $entry->{time}        = _time($f)        if $options->{show}{time};
    }
    $files{$file} = $entry;
  }

  my $data = {
    devel_cover_version => $Devel::Cover::Inc::VERSION,
    runs                => _runs($db),
    summary             => $db->{summary},
    files               => \%files,
  };

  my $outfile = $options->{option}{outputfile} // "cover.json";
  $outfile = "$options->{outputdir}/$outfile" unless $outfile =~ m{^/};
  my $io = Devel::Cover::DB::IO::JSON->new(options => "pretty");
  $io->write($data, $outfile);

  dcinfo "JSON output written to $outfile";
}

"
Was it destiny
I don't know yet
Was it just by chance? Could this be Kismet?
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Report::Json - Detailed JSON backend for Devel::Cover

=head1 SYNOPSIS

 cover -report json
 cover -report json -outputfile coverage-detail.json

=head1 DESCRIPTION

This module provides detailed JSON output for coverage data, suitable for
machine reading.  Unlike L<Devel::Cover::Report::Json_summary>, which outputs
only per-file summary statistics, this report includes full per-line,
per-criterion coverage detail for every covered file, plus condition truth
tables and timing data.

It is designed to be called from the C<cover> program.

=head1 OPTIONS

=over 4

=item --outputfile=FILE

Name of the output file (default C<cover.json>).

=back

=head1 OUTPUT FORMAT

The output format may evolve as Devel::Cover changes, but we aim to keep it
stable.

The output file is C<cover.json> in the output directory (default
C<cover_db/>). The top-level keys are:

=over 4

=item devel_cover_version

The version of Devel::Cover that produced the file.

=item runs

Array of run metadata objects, identical to the C<json_summary> report output.

=item summary

Hash of coverage summaries keyed by file path, plus a C<Total> entry for
aggregate statistics across all files.  Identical in structure to the
C<json_summary> report output.

=item files

Hash keyed by file path.  Each value is an object containing C<meta> (always
present) and per-criterion sub-objects when the corresponding criterion was
selected and the file was compiled.

The per-criterion keys are: C<statements>, C<branches>, C<conditions>,
C<condition_truth_tables>, C<subroutines>, C<pod>, C<time>.  Within each
criterion, keys are source line numbers and values are arrays of coverage
objects for that line.

=back

Example structure:

  {
    "devel_cover_version": "1.53",
    "runs": [ { "run": "...", "perl": "5.38.0", ... } ],
    "summary": {
      "Total":          { "statement": { "covered": 95, "total": 100,
                                          ... }, ... },
      "lib/Foo/Bar.pm": { "statement": { ... }, ... }
    },
    "files": {
      "lib/Foo/Bar.pm": {
        "meta":        { "uncompiled": 0, "digest": "sha1...",
                          "counts": {} },
        "statements":  { "10": [ { "covered": 5, "uncoverable": 0,
                                    "error": 0 } ] },
        "branches":    { "17": [ { "text": "if $x", "covered": [3,0],
                                    "uncoverable": [0,0], "error": 1 } ] },
        "conditions":  { "30": [ { "type": "and_2", "text": "$x && $y",
                                    "headers": ["left","right"],
                                    "covered": [3,0], "uncoverable": [0,0],
                                    "error": 1 } ] },
        "condition_truth_tables": {
          "30": [ { "expr": "$x && $y", "percentage": 50,
                    "rows": [ { "inputs": [0,0], "result": 0,
                                "covered": 1 } ] } ] },
        "subroutines": { "50": [ { "name": "frob", "covered": 0,
                                    "uncoverable": 0, "error": 1 } ] },
        "pod":         { "60": [ { "covered": 0, "uncoverable": 0,
                                    "error": 1 } ] },
        "time":        { "10": [ { "value": 42 } ] }
      }
    }
  }

=head1 SEE ALSO

L<Devel::Cover>, L<Devel::Cover::Report::Json_summary>

=head1 LICENCE

Copyright 2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

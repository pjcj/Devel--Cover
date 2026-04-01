package Devel::Cover::Report::Json_detailed;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use Devel::Cover::DB::IO::JSON;

sub _runs ($db) {
  my @runs;
  for my $r (sort { $a->{start} <=> $b->{start} } $db->runs) {
    push @runs,
      { map { $_ => $r->$_ }
        qw( run perl OS dir name version abstract start finish ) };
  }
  \@runs
}

sub _statements ($f) {
  my $criterion = $f->statement or return undef;
  my %out;
  for my $line ($criterion->items) {
    my @entries;
    for my $s ($criterion->location($line)->@*) {
      push @entries, {
        covered     => $s->covered     + 0,
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
        covered     => [ map { $b->covered($_)     + 0 } 0 .. $b->total - 1 ],
        uncoverable => [ map { $b->uncoverable($_) ? 1 : 0 } 0 .. $b->total - 1 ],
        error       => $b->error ? 1 : 0,
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
        covered     => [ map { $c->covered($_)     + 0 } 0 .. $c->total - 1 ],
        uncoverable => [ map { $c->uncoverable($_) ? 1 : 0 } 0 .. $c->total - 1 ],
        error       => $c->error ? 1 : 0,
      };
    }
    $out{$line} = \@entries;
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
        covered     => $s->covered     + 0,
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
        covered     => $p->covered     + 0,
        uncoverable => $p->uncoverable ? 1 : 0,
        error       => $p->error       ? 1 : 0,
      };
    }
    $out{$line} = \@entries;
  }
  \%out
}

sub report ($pkg, $db, $options) {
  my %sum_options = map { $_ => 1 } grep !/path|time/, $db->all_criteria, "force";
  $db->calculate_summary(%sum_options);

  my %files;
  for my $file ($options->{file}->@*) {
    my $f = $db->cover->file($file);
    next if $f->{meta}{uncompiled};

    $files{$file} = {
      statements  => $options->{show}{statement}  ? _statements($f)  : undef,
      branches    => $options->{show}{branch}     ? _branches($f)    : undef,
      conditions  => $options->{show}{condition}  ? _conditions($f)  : undef,
      subroutines => $options->{show}{subroutine} ? _subroutines($f) : undef,
      pod         => $options->{show}{pod}        ? _pod($f)         : undef,
    };
  }

  my $data = {
    runs    => _runs($db),
    summary => $db->{summary},
    files   => \%files,
  };

  my $outfile = "$options->{outputdir}/cover_detailed.json";
  print "JSON detail sent to $outfile\n";

  my $io = Devel::Cover::DB::IO::JSON->new(options => "pretty");
  $io->write($data, $outfile);
}

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Report::Json_detailed - Detailed JSON backend for Devel::Cover

=head1 SYNOPSIS

 cover -report json_detailed

=head1 DESCRIPTION

This module provides detailed JSON output for coverage data, suitable for
machine reading.  Unlike L<Devel::Cover::Report::Json>, which outputs only
per-file summary statistics, this report includes full per-line, per-criterion
coverage detail for every covered file.

It is designed to be called from the C<cover> program.

=head1 OUTPUT FORMAT

The output format might change over time as Devel::Cover itself changes, but
we'll try to keep things fairly stable.

The output file is C<cover_detailed.json> in the output directory (default:
C<cover_db/>).  The top-level keys are:

=over 4

=item runs

Array of run metadata objects, identical to the C<json> report output.

=item summary

Hash of coverage summaries keyed by file path, plus a C<Total> entry for
aggregate statistics across all files.  Identical in structure to the
C<json> report output.

=item files

Hash keyed by file path.  Each value is an object with up to five keys:
C<statements>, C<branches>, C<conditions>, C<subroutines>, C<pod>.  A key
is C<null> when the corresponding criterion was not selected or has no data.

Within each criterion, keys are source line numbers and values are arrays of
coverage objects for that line.  A line may have multiple entries when several
constructs appear at the same source location.

=back

Example structure:

 {
   "runs": [ { "run": "...", "perl": "5.38.0", ... } ],
   "summary": {
     "Total":          { "statement": { "covered": 95, "total": 100, ... }, ... },
     "lib/Foo/Bar.pm": { "statement": { ... }, ... }
   },
   "files": {
     "lib/Foo/Bar.pm": {
       "statements":  { "10": [ { "covered": 5, "uncoverable": 0, "error": 0 } ] },
       "branches":    { "17": [ { "text": "if $x", "covered": [3,0],
                                  "uncoverable": [0,0], "error": 1 } ] },
       "conditions":  { "30": [ { "type": "and_2", "text": "$x && $y",
                                  "headers": ["left","right"],
                                  "covered": [3,0], "uncoverable": [0,0],
                                  "error": 1 } ] },
       "subroutines": { "50": [ { "name": "frob", "covered": 0,
                                  "uncoverable": 0, "error": 1 } ] },
       "pod":         { "60": [ { "covered": 0, "uncoverable": 0,
                                  "error": 1 } ] }
     }
   }
 }

=head1 SEE ALSO

L<Devel::Cover>, L<Devel::Cover::Report::Json>

=head1 LICENCE

Copyright 2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

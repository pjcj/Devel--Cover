# Copyright 2014-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Report::Json_summary;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use Devel::Cover::Criterion    ();
use Devel::Cover::DB::IO::JSON ();
use Devel::Cover::Log          qw( dcinfo );
use Getopt::Long               qw( GetOptions );

sub add_runs ($db) {
  my @runs;
  for my $r (reverse $db->runs) {
    push @runs,
      { map { $_ => $r->$_ }
        qw( run perl OS dir name version abstract start finish ) };
  }
  \@runs
}

sub get_options ($self, $opt) {
  $opt->{option}{outputfile} = "cover.json";
  die "Invalid command line options"
    unless GetOptions($opt->{option}, qw( outputfile=s ));
}

sub report ($pkg, $db, $options) {
  my %options = map { $_ => 1 } grep {
    $_ eq "total"
      || Devel::Cover::Criterion->criterion_class($_)->measures_coverage
  } $db->all_criteria;
  my $summary = $db->file_summary($options->{file}, %options);

  my $json = { runs => add_runs($db), summary => $summary };

  my $path = $options->{option}{outputfile} // "cover.json";
  $path = "$options->{outputdir}/$path" unless $path =~ m{^/};
  my $io = Devel::Cover::DB::IO::JSON->new(options => "pretty");

  $io->write($json, $path);

  dcinfo "JSON output written to $path";
}

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Report::Json_summary - Summary JSON backend for Devel::Cover

=head1 SYNOPSIS

 cover -report json_summary

=head1 DESCRIPTION

This module provides summary-only JSON output for coverage data, suitable for
generating coverage badges and aggregate metrics.  The output contains per-file
and total coverage percentages by criterion, but no per-line detail.  It is the
format consumed by L<cpancover>.

For full per-line, per-criterion coverage detail see
L<Devel::Cover::Report::Json>.

It is designed to be called from the C<cover> program.

=head1 SEE ALSO

L<Devel::Cover>, L<Devel::Cover::Report::Json>

=head1 LICENCE

Copyright 2014-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

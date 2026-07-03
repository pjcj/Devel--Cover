# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Mcdc;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use base "Devel::Cover::Criterion";

sub total     ($self) { scalar $self->[0]->@* }
sub values    ($self) { $self->[0]->@* }
sub text      ($self) { $self->[1]{text} }
sub labels    ($self) { $self->[1]{labels} // [] }
sub criterion ($self) { "mcdc" }

# True for a decision too wide to analyse; see LIMITATIONS below
sub unanalysed ($self) { $self->[1]{unanalysed} ? 1 : 0 }

sub covered ($self, $i = undef) {
  defined $i ? $self->[0][$i] : scalar grep $_, $self->[0]->@*
}

sub uncoverable ($self, $i = undef) {
  defined $i ? $self->[2][$i] : scalar grep $_, ($self->[2] // [])->@*
}

sub missing ($self) {
  my $cov = $self->[0];
  my $unc = $self->[2] // [];
  my $lab = $self->labels;
  [map $lab->[$_], grep !$cov->[$_] && !$unc->[$_], 0 .. $#$cov]
}

sub percentage ($self) {
  my $t = $self->total;
  $t ? int($self->covered / $t * 100) : 0
}

sub error ($self, $c = undef) {
  return $self->err_chk($self->covered($c), $self->uncoverable($c))
    if defined $c;
  my $e = 0;
  for my $i (0 .. $self->total - 1) {
    $e++ if $self->err_chk($self->covered($i), $self->uncoverable($i));
  }
  $e
}

sub calculate_summary ($self, $db, $file) {
  my $s = $db->{summary};
  $self->aggregate($s, $file, "total",       $self->total);
  $self->aggregate($s, $file, "uncoverable", $self->uncoverable);
  $self->aggregate($s, $file, "covered",     $self->covered);
  $self->aggregate($s, $file, "error",       $self->error);
}

"
The answer, my friend, is blowin' in the wind
The answer is blowin' in the wind
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Mcdc - Modified Condition/Decision Coverage criterion

=head1 SYNOPSIS

 use Devel::Cover::Mcdc;

=head1 DESCRIPTION

Criterion class for Modified Condition/Decision Coverage (MC/DC). Aggregates
per-decision MC/DC results across files and exposes the standard
L<Devel::Cover::Criterion> interface (C<total>, C<covered>, C<percentage>,
C<error>) for reporting.

MC/DC is a parallel criterion alongside C<condition>.  It derives from the
condition truth tables already collected by the existing runtime
instrumentation, so no new XS data collection is required.

See L<Devel::Cover::Tutorial/2.5 Modified condition/decision coverage> for an
introduction to the metric and a worked example, and
L<Devel::Cover::Mcdc::Analyser> for the per-decision analyser this class wraps.

=head1 USAGE

MC/DC is part of the default coverage set, so the usual invocations include
it without any extra flags:

 cover -test

To request MC/DC alongside a narrower selection, name both C<condition> and
C<mcdc> on the command line:

 cover -coverage condition,mcdc -test

MC/DC is derived from the condition truth tables collected at runtime.
C<condition> must therefore be active at collection time; selecting C<mcdc>
alone leaves no condition data to analyse and produces an empty MC/DC
report.

Reports show MC/DC in two places: a per-file C<mcdc> percentage column in
the summary, and a per-decision detail block listing each atomic condition
whose independence pair was missing.

=head1 LIMITATIONS

A decision with more than 16 conditions exceeds the analysis limit.  Such a
decision counts as 0 of its width in the percentages and appears in reports
with an error flag and a "too many conditions" note in place of the
missing-conditions list.  Generating a report warns, naming the file and
line; C<-silent> suppresses the warning.  Any C<# uncoverable mcdc> markers
on such a decision are ignored.

The remedy is to split the decision with an intermediate variable:

 my $r = $c1 || $c2 || ... || $c17 || $c18;          # too wide

 my $left = $c1 || $c2 || ... || $c9;                # analysed
 my $r    = $left || $c10 || ... || $c18;            # analysed

The split form needs no extra test cases, preserves short-circuiting, and
lets every condition be analysed.

=head1 SEE ALSO

 Devel::Cover::Criterion
 Devel::Cover::Mcdc::Analyser
 Devel::Cover::Condition_table
 cover

=head1 METHODS

=head1 LICENCE

Copyright 2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

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

sub covered     ($self)             { scalar grep $_, $self->[0]->@* }
sub total       ($self)             { scalar $self->[0]->@* }
sub values      ($self)             { $self->[0]->@* }
sub text        ($self)             { $self->[1]{text} }
sub labels      ($self)             { $self->[1]{labels} // [] }
sub criterion   ($self)             { "mcdc" }
sub uncoverable ($self, $i = undef) { 0 }

sub missing ($self) {
  my $cov = $self->[0];
  my $lab = $self->labels;
  [map $lab->[$_], grep !$cov->[$_], 0 .. $#$cov]
}

sub percentage ($self) {
  my $t = $self->total;
  $t ? int($self->covered / $t * 100) : 0
}

sub error ($self) { $self->total - $self->covered }

sub calculate_summary ($self, $db, $file) {
  my $s = $db->{summary};
  $self->aggregate($s, $file, "total",   $self->total);
  $self->aggregate($s, $file, "covered", $self->covered);
  $self->aggregate($s, $file, "error",   $self->error);
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

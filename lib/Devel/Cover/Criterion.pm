# Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Criterion;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

for my $class (qw(
  Statement
  Branch
  Condition
  Condition_or_2
  Condition_or_3
  Condition_and_2
  Condition_and_3
  Condition_xor_4
  Mcdc
  Subroutine
  Pod
  Time
))
{
  eval "require Devel::Cover::$class; 1"
    or die "Failed to load Devel::Cover::$class: $@";
}

my @Criteria = qw( statement branch condition mcdc subroutine pod time );

sub criterion_names ($class) { @Criteria }

sub criterion_class ($class, $name) { "Devel::Cover::" . ucfirst $name }

sub coverage_criteria ($class) {
  grep $class->criterion_class($_)->measures_coverage, @Criteria
}

sub editor_criteria ($class) {
  grep defined $class->criterion_class($_)->sign_letter, @Criteria
}

sub shortname        ($class) { $class->criterion }
sub display_name     ($class) { ucfirst $class->criterion }
sub display_mode     ($class) { "percentage" }
sub detail_criterion ($class) { undef }

sub has_detail_page ($class) {
  ($class->detail_criterion // "") eq $class->criterion
}

sub measures_coverage ($class) { 1 }
sub sign_letter       ($class) { undef }
sub indexed           ($class) { 0 }

sub coverage    ($self) { $self->[0] }
sub information ($self) { $self->[1] }

sub uncoverable ($self) { "n/a" }
sub covered     ($self) { "n/a" }
sub total       ($self) { "n/a" }
sub percentage  ($self) { "n/a" }
sub error       ($self) { "n/a" }
sub text        ($self) { "n/a" }
sub values      ($self) { [$self->covered] }

sub criterion ($self) {
  require Carp;
  Carp::confess("criterion() must be overridden")
}

sub uncoverable_classes ($class) { qw( default ignore_covered_err ) }

sub err_chk ($self, $covered, $uncoverable) {
  no warnings qw( once uninitialized );
  $Devel::Cover::Ignore_covered_err || $uncoverable eq "ignore_covered_err"
    ? !($covered || $uncoverable)
    : !($covered xor $uncoverable)
}

sub simple_error ($self) {
  $self->err_chk($self->covered, $self->uncoverable)
}

sub coverage_state ($self, $i = undef) {
  my $covered     = defined $i ? $self->covered($i)     : $self->covered;
  my $uncoverable = defined $i ? $self->uncoverable($i) : $self->uncoverable;
  return "uncovered" unless $covered || $uncoverable;
  return "covered"   unless $uncoverable;
  return "excused"   unless $covered;
  $self->err_chk($covered, $uncoverable) ? "stale" : "covered"
}

sub calculate_percentage ($class, $db, $s) {
  return unless $s;
  my $errors = $s->{error} || 0;
  $s->{percentage} = $s->{total} ? 100 - $errors * 100 / $s->{total} : 100;
}

sub aggregate ($self, $s, $file, $keyword, $t) {
  my $name = $self->criterion;
  $t                            = int $t;
  $s->{$file}{$name}{$keyword} += $t;
  $s->{$file}{total}{$keyword} += $t;
  $s->{Total}{$name}{$keyword} += $t;
  $s->{Total}{total}{$keyword} += $t;
}

sub calculate_summary ($self, $db, $file) {
  my $s = $db->{summary};
  $self->aggregate($s, $file, "total",       $self->total);
  $self->aggregate($s, $file, "uncoverable", 1) if $self->uncoverable;
  $self->aggregate($s, $file, "covered",     1) if $self->covered;
  $self->aggregate($s, $file, "error",       1) if $self->error;
}

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Criterion - Base class for coverage criteria

=head1 SYNOPSIS

 use Devel::Cover::Criterion;

=head1 DESCRIPTION

Abstract base class for all the coverage criteria. It also carries the
canonical criterion list and per-criterion metadata as class methods, so
reporters can ask about a criterion instead of hardcoding names, regexes
and lists.

=head1 SEE ALSO

 Devel::Cover

=head1 CLASS METHODS

=head2 criterion_names

  my @names = Devel::Cover::Criterion->criterion_names;

Return the canonical criterion names in order. The
C<@Devel::Cover::DB::Criteria> and C<@Devel::Cover::DB::Criteria_short>
lists derive from this metadata.

=head2 criterion_class ($name)

  my $class = Devel::Cover::Criterion->criterion_class("branch");

Return the class implementing the named criterion.

=head2 coverage_criteria

Return the criterion names that measure coverage - every criterion
except time.

=head2 editor_criteria

Return the criterion names shown by the editor reports, in canonical
order. The Vim and Nvim templates place signs last-in-list-wins, so this
order is the sign display priority.

=head2 uncoverable_classes

Return the class words an uncoverable comment may carry - C<default>
and C<ignore_covered_err>. The comment parser rejects anything else.

=head1 CRITERION METADATA

Each criterion class answers these, overriding the base defaults.

=head2 shortname

The abbreviation used in summary headers and C<-coverage> options, such
as C<stmt> or C<bran>.

=head2 display_name

The human-readable name, such as C<Statement> or C<MC/DC>.

=head2 display_mode

Either C<count> or C<percentage> - which of C<covered> and C<percentage>
reporters display for a single value.

=head2 detail_criterion

The criterion name whose per-file detail page this criterion's values
link to, or undef when there is none. Pod links to the subroutine page.

=head2 has_detail_page

True only when a criterion owns its own detail page - branch, condition,
mcdc and subroutine.

=head2 measures_coverage

False only for time, which is timing data rather than a coverage
criterion.

=head2 sign_letter

The editor sign character, such as C<S> or C<B>. Undef for time, which
has no sign.

=head2 indexed

True for criteria holding a value per path or outcome - branch,
condition and mcdc - whose C<covered>, C<uncoverable>, C<error> and
C<coverage_state> take an index. False for the single-value criteria.

=head1 METHODS

There is no constructor. L<Devel::Cover::DB> blesses each entry it reads
from the database into the class for its criterion, and into the
C<Devel::Cover::Condition_*> subclass named by the type of the entry where
there is one. An entry is an array. Element 0 holds the coverage, element
1 the structure information and element 2 the uncoverable flag or flags.

=head2 coverage

Return the raw coverage in element 0. This is a count for the
single-value criteria and an array of counts for the indexed ones.

=head2 information

Return the structure information in element 1, such as the text of a
branch or the name of a subroutine.

=head2 uncoverable

Return the uncoverable flag. The base returns C<n/a>.

=head2 covered

Return the number of values covered. The base returns C<n/a>.

=head2 total

Return the number of values. The base returns C<n/a>.

=head2 percentage

Return the share of values not in error, as an integer. The base
returns C<n/a>.

=head2 error

Return the number of values in error. The base returns C<n/a>.

=head2 text

Return the source text of the construct, for the criteria which keep
it. The base returns C<n/a>.

=head2 values

Return the covered value as a one-element array reference. The indexed
criteria override this to return all their counts.

=head2 criterion

Return the criterion name, such as C<statement>. Each subclass must
override this, since the base dies.

=head2 err_chk ($covered, $uncoverable)

Return true when a value is in error. A value is right when it is
covered or marked uncoverable but not both. Under C<-ignore_covered_err>,
or when the marker has the C<ignore_covered_err> class, a covered value
with a marker counts as right, and only an uncovered value with no marker
is in error.

=head2 simple_error

Return the result of C<err_chk> on the single covered and uncoverable
values. The single-value criteria use this as their C<error>.

=head2 coverage_state ($i)

  my $state = $o->coverage_state;
  my $state = $o->coverage_state($i);

Return the name of the state the construct is in, combining coverage
with the uncoverable flag:

  covered  uncoverable  state
        1            0  covered
        0            0  uncovered
        0            1  excused
        1            1  stale

A stale marker - a construct which runs despite being marked
uncoverable - is normally an error, because the marker no longer tells
the truth. It is forgiven, and reported as covered, under
C<-ignore_covered_err> or when the marker carries the
C<ignore_covered_err> class. Criteria holding several values, such as
branch, take the index of the value to ask about.

=head2 calculate_percentage ($db, $summary)

Set the C<percentage> key of the summary from its C<total> and C<error>
counts. A summary with no total is 100. L<Devel::Cover::Time> overrides
this, since its total is not a count of constructs.

=head2 aggregate ($summary, $file, $keyword, $count)

Add the count to the summary under the keyword, for this criterion and
for all criteria together, under both the file and the C<Total> key.

=head2 calculate_summary ($db, $file)

Add this value to the summary of the database. The base adds the total
and one each for covered, uncoverable and error where they apply. The
indexed criteria override this to add their counts.

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

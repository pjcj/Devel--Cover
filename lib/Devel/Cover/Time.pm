# Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Time;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use base "Devel::Cover::Criterion";

sub uncoverable ($self) { 0 }
sub covered     ($self) { $$self }
sub total       ($self) { 1 }
sub percentage  ($self) { $$self ? 100 : 0 }
sub error       ($self) { 0 }
sub criterion   ($self) { "time" }

sub display_mode      ($class) { "count" }
sub measures_coverage ($class) { 0 }

sub calculate_summary ($self, $db, $file) {
  $db->{summary}{$file}{time}{total} += $$self;
  $db->{summary}{Total}{time}{total} += $$self;
}

sub calculate_percentage ($class, $db, $s) {
  my $t = $db->{summary}{Total}{time}{total};
  $s->{percentage} = $t ? $s->{total} * 100 / $t : 100;
}

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Time - Execution time criterion

=head1 SYNOPSIS

 use Devel::Cover::Time;

=head1 DESCRIPTION

Module for storing time coverage information.

=head1 SEE ALSO

 Devel::Cover::Criterion

=head1 METHODS

The entry is a reference to a scalar holding the time spent on the
statement, in microseconds.

=head2 uncoverable

Return 0, since time is not a coverage criterion.

=head2 covered

Return the time spent.

=head2 total

Return 1.

=head2 percentage

Return 100 when any time was spent, otherwise 0.

=head2 error

Return 0.

=head2 criterion

Return C<time>.

=head2 display_mode

Return C<count>.

=head2 measures_coverage

Return false.

=head2 calculate_summary ($db, $file)

Add the time spent to the totals for the file and for the whole database.

=head2 calculate_percentage ($db, $summary)

Set the C<percentage> key of the summary to the share of the total time
of the database that this summary covers. A database with no time
recorded gives 100.

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

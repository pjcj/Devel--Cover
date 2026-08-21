# Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::DB::File;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use Devel::Cover::Criterion ();
# use Devel::Cover::Dumper;

sub calculate_summary ($self, $db, $file, $options) {
  my $s = $db->{summary}{$file} ||= {};
  if ($self->{meta}{uncompiled}) {
    my $counts = $self->{meta}{counts} // return;
    my $t      = $db->{summary};
    for my $c (keys %$counts) {
      next unless $options->{$c};
      next unless $counts->{$c};  # skip criteria with nothing to cover
      $s->{$c}
        = { covered => 0, total => $counts->{$c}, error => $counts->{$c} };
      for my $k (qw( total covered error )) {
        $s->{total}{$k}        += $s->{$c}{$k};
        $t->{Total}{$c}{$k}    += $s->{$c}{$k};
        $t->{Total}{total}{$k} += $s->{$c}{$k};
      }
    }
    return;
  }

  for my $criterion ($self->items) {
    next unless $options->{$criterion};
    for my $location ($self->$criterion()->locations) {
      for my $cover (@$location) {
        $cover->calculate_summary($db, $file);
      }
    }
  }
}

sub calculate_percentage ($self, $db, $s) {
  if ($self->{meta}{uncompiled}) {
    my $counts = $self->{meta}{counts} // return;
    for my $c (keys %$counts) {
      Devel::Cover::Criterion->calculate_percentage($db, $s->{$c});
    }
    Devel::Cover::Criterion->calculate_percentage($db, $s->{total});
    return;
  }

  # print STDERR Dumper $s;
  for my $criterion ($self->items) {
    next unless exists $s->{$criterion};
    my $c = "Devel::Cover::\u$criterion";
    # print "$c\n";
    $c->calculate_percentage($db, $s->{$criterion});
  }
  Devel::Cover::Criterion->calculate_percentage($db, $s->{total});
  # print STDERR Dumper $s;
}

"
Fate
Up against your will
Through the thick and thin
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover::DB::File - Coverage data for one source file

=head1 SYNOPSIS

 use Devel::Cover::DB::File;

=head1 DESCRIPTION

A C<Devel::Cover::DB::File> object holds the coverage for one source file in a
L<Devel::Cover::DB>.  It is a hash keyed by criterion name, so
C<< $file->statement >> gives back a C<Devel::Cover::DB::Criterion>.  Those
accessors come from C<Devel::Cover::DB::Base>, and L<Devel::Cover::DB> describes
them.  A C<meta> key sits beside the criteria, holding what is known about the
file itself rather than any coverage of it.

Nothing constructs one of these directly.  L<Devel::Cover::DB> blesses each
entry of the cover hash as the database is read, so you reach a file with
C<< $db->cover->file($name) >>.

A file added by the F<cover> option C<-select_dir> which no test ever loaded has
no criteria at all.  It carries only a C<meta> entry marking it uncompiled,
together with the counts L<Devel::Cover::Static> estimates from the source when
L<PPI> is installed.  Both methods below take a separate path for such a file
and report every construct in it as uncovered.

=head1 METHODS

=head2 calculate_summary

  $file->calculate_summary($db, $name, \%options);

Add this file's counts to C<< $db->{summary}{$name} >> and to the running
C<Total>.  Criteria without a true value in C<%options> are skipped.  For a
compiled file each coverage object does its own share of the work.

=head2 calculate_percentage

  $file->calculate_percentage($db, $summary);

Turn the counts gathered in C<$summary> into percentages, criterion by criterion
and then for the total.  Call it after L</calculate_summary>.

=head1 SEE ALSO

 Devel::Cover

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

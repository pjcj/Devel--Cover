# Copyright 2004-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Report::Sort;

use strict;
use warnings;

# VERSION

use Devel::Cover::DB;

sub print_sort {
  my ($db, $options) = @_;
  my %runs;
  my @collected = grep $_ ne "time", @{ $options->{coverage} };
  # use Devel::Cover::Dumper; print Dumper [$db->runs];
  for my $r (sort { $a->{start} <=> $b->{start} } $db->runs) {
    print "Run:          ", $r->run,                        "\n";
    print "Perl version: ", $r->perl,                       "\n";
    print "OS:           ", $r->OS,                         "\n";
    print "Start:        ", scalar gmtime $r->start / 1e6,  "\n";
    print "Finish:       ", scalar gmtime $r->finish / 1e6, "\n";
    # use Devel::Cover::Dumper; print Dumper $r;

    @{ $runs{ $r->run } }{ "vec", "size" } = ("", 0);
    my $run = $runs{ $r->run };
    # use Devel::Cover::Dumper; print Dumper $run;
    my $vec = $r->vec;
    for my $file (@{ $options->{file} }) {
      # print "$file\n";
      for my $criterion (@collected) {
        my ($v, $sz) = @{ $vec->{$file}{$criterion} }{ "vec", "size" };
        $sz |= 0;
        printf "$file:%10s %5d: ", $criterion, $sz;
        unless ($sz) {
          print "\n";
          next;
        }
        for (0 .. $sz - 1) {
          print vec $v, $_, 1;
          vec($run->{vec}, $run->{size}++, 1) = vec $v, $_, 1;
        }
        print "\n";
      }
    }
    $run->{count} += vec $run->{vec}, $_, 1 for 0 .. $run->{size} - 1;
    print "Vec:          ";
    print vec $run->{vec}, $_, 1 for 0 .. $run->{size} - 1;
    print "\n";
    print "Count:        $run->{count} / $run->{size}\n\n";
  }
}

sub report {
  my ($pkg, $db, $options) = @_;
  print_sort($db, $options);
}

1

__END__

=head1 NAME

Devel::Cover::Report::Sort - backend for Devel::Cover

=head1 SYNOPSIS

 cover -report sort

=head1 DESCRIPTION

This module reports coverage runs in an optimal order.
It is designed to be called from the C<cover> program.

=head1 SEE ALSO

 Devel::Cover

=head1 LICENCE

Copyright 2004-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

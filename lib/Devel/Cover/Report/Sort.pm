# Copyright 2004-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Report::Sort;

use v5.20.0;
use strict;
use warnings;
use feature qw( postderef say signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

sub print_sort ($db, $options) {
  my %runs;
  my @collected = grep $_ ne "time", $options->{coverage}->@*;
  for my $r (sort { $a->{start} <=> $b->{start} } $db->runs) {
    say "Run:          ", $r->run;
    say "Perl version: ", $r->perl;
    say "OS:           ", $r->OS;
    say "Start:        ", scalar gmtime $r->start / 1e6;
    say "Finish:       ", scalar gmtime $r->finish / 1e6;

    $runs{ $r->run }->@{ "vec", "size" } = ("", 0);
    my $run = $runs{ $r->run };
    my $vec = $r->vec;
    for my $file (
      grep !$db->cover->file($_)->{meta}{uncompiled},
      $options->{file}->@*,
    ) {
      for my $criterion (@collected) {
        my ($v, $sz) = $vec->{$file}{$criterion}->@{ "vec", "size" };
        $sz |= 0;
        printf "$file:%10s %5d: ", $criterion, $sz;
        unless ($sz) {
          say "";
          next;
        }
        for (0 .. $sz - 1) {
          print vec $v, $_, 1;
          vec($run->{vec}, $run->{size}++, 1) = vec $v, $_, 1;
        }
        say "";
      }
    }
    $run->{count} += vec $run->{vec}, $_, 1 for 0 .. $run->{size} - 1;
    print "Vec:          ";
    print vec $run->{vec}, $_, 1 for 0 .. $run->{size} - 1;
    say "";
    say "Count:        $run->{count} / $run->{size}\n";
  }
}

sub report ($pkg, $db, $options) {
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

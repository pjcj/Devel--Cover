# Copyright 2001-2017, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# ############################################################################ #
# 2006-09-14 Denis Howe
# Cloned from 0.59 Text.pm and hacked to give a minimal output in a
# format similar to that output by Perl itself so that it's easier to
# step through the untested locations with Emacs compilation mode
# Copyright assigned to Paul Johnson
# ############################################################################ #

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Report::Compilation;

use strict;
use warnings;

# VERSION

use Devel::Cover::DB;

# TODO - uncoverable code?

sub print_statement {
    my ($db, $file, $options) = @_;

    my $statements = $db->cover->file($file)->statement or return;

    for my $location ($statements->items) {
        my $l = $statements->location($location);
        for my $statement (@$l) {
            next if $statement->covered;
            print "Uncovered statement at $file line $location:\n";
        }
    }
}

sub print_branches {
    my ($db, $file, $options) = @_;

    my $branches = $db->cover->file($file)->branch or return;

    for my $location (sort { $a <=> $b } $branches->items) {
        for my $b (@{$branches->location($location)}) {
            next unless $b->error;

            # One or both paths from this branch weren't reached.
            # $b->covered(0) and (1) say whether the first and second
            # paths were reached.  If the branch condition text begins
            # with "unless" then the meanings of 0 and 1 are swapped.
            # The output is easier to understand if we strip off
            # "unless" and say whether the remaining condition was
            # true or false.

            my $text = $b->text;
            my ($t, $f) = map $b->covered($_),
                $text =~ s/^(if|unless) // && $1 eq "unless" ? (1, 0) : (0, 1);
            # TODO - uncoverable code?
            print "Branch never ",
                $t ? ($f ? "???" : "false") : ($f ? "true" : "reached"),
                " at $file line $location: $text\n";
        }
    }
}

sub print_conditions {
    my ($db, $file, $options) = @_;

    my $conditions = $db->cover->file($file)->condition or return;

    my $template = sub { "%-5s %3s %6s " . ( "%6s " x shift ) . "  %s\n" };

    my %r;
    for my $location (sort { $a <=> $b } $conditions->items) {
        my %seen;
        for my $c (@{$conditions->location($location)}) {
            push @{$r{$c->type}}, [ $c, $seen{$c->type}++ ? "" : $location ];
        }
    }

    my %seen;
    for my $type (sort keys %r) {
        my $tpl;
        for (@{$r{$type}}) {
            my ($c, $location) = @$_;
            next unless $c->error;
            my @headers = @{$c->headers};
            print "Uncovered condition (", join(", ",
                map (!$c->covered($_) ? $headers[$_] : (), 0..$c->total-1)),
                ") at $file line $location: ", $c->text, "\n";
        }
    }
}

sub print_subroutines {
    my ($db, $file, $options) = @_;

    my $subroutines = $db->cover->file($file)->subroutine or return;

    for my $location ($subroutines->items) {
        my $l = $subroutines->location($location);
        for my $sub (@$l) {
            next if $sub->covered;
            print "Uncovered subroutine ", $sub->name,
                  " at $file line $location\n";
        }
    }
}

sub report {
    my ($pkg, $db, $options) = @_;

    for my $file (@{$options->{file}}) {
        print_statement  ($db, $file, $options) if $options->{show}{statement};
        print_branches   ($db, $file, $options) if $options->{show}{branch};
        print_conditions ($db, $file, $options) if $options->{show}{condition};
        print_subroutines($db, $file, $options) if $options->{show}{subroutine};
    }
}

1

__END__

=head1 NAME

Devel::Cover::Report::Compilation - backend for Devel::Cover

=head1 SYNOPSIS

 cover -report compilation

=head1 DESCRIPTION

This module provides a textual reporting mechanism for coverage data.
It is designed to be called from the C<cover> program.

It produces one report per line, in a format like Perl's own compilation error
messages.  This makes it easy to, e.g. use Emacs compilation mode to step
through the reports.

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2001-2017, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

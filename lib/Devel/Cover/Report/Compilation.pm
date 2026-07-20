# Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Report::Compilation;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

# TODO - uncoverable code?

sub print_statement ($db, $file, $) {
  my $statements = $db->cover->file($file)->statement or return;

  for my $location (sort { $a <=> $b } $statements->items) {
    for my $statement ($statements->location($location)->@*) {
      next if $statement->covered;
      print "Uncovered statement at $file line $location\n";
    }
  }
}

sub print_branches ($db, $file, $) {
  my $branches = $db->cover->file($file)->branch or return;

  for my $location (sort { $a <=> $b } $branches->items) {
    for my $b ($branches->location($location)->@*) {
      next unless $b->error;

      # One or both paths from this branch weren't reached. $b->covered(0) and
      # (1) say whether the first and second paths were reached.  If the branch
      # condition text begins with "unless" then the meanings of 0 and 1 are
      # swapped. The output is easier to understand if we strip off "unless" and
      # say whether the remaining condition was true or false.

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

sub print_conditions ($db, $file, $) {
  my $conditions = $db->cover->file($file)->condition or return;

  my %r;
  for my $location (sort { $a <=> $b } $conditions->items) {
    my %seen;
    for my $c ($conditions->location($location)->@*) {
      push $r{ $c->type }->@*, [$c, $seen{ $c->type }++ ? "" : $location];
    }
  }

  for my $type (sort keys %r) {
    for ($r{$type}->@*) {
      my ($c, $location) = @$_;
      next unless $c->error;
      my @headers = $c->headers->@*;
      print "Uncovered condition (",
        join(", ", map !$c->covered($_) ? $headers[$_] : (),
          0 .. $c->total - 1), ") at $file line $location: ", $c->text, "\n";
    }
  }
}

sub print_mcdc ($db, $file, $) {
  my $mcdc = $db->cover->file($file)->mcdc or return;

  for my $location (sort { $a <=> $b } $mcdc->items) {
    for my $m ($mcdc->location($location)->@*) {
      next unless $m->error;
      if ($m->unanalysed) {
        print "Unanalysed MC/DC decision (too many conditions) ",
          "at $file line $location: ", $m->text, "\n";
        next;
      }
      print "Uncovered MC/DC pair (", join(", ", $m->missing->@*),
        ") at $file line $location: ", $m->text, "\n";
    }
  }
}

sub print_subroutines ($db, $file, $) {
  my $subroutines = $db->cover->file($file)->subroutine or return;

  for my $location (sort { $a <=> $b } $subroutines->items) {
    for my $sub ($subroutines->location($location)->@*) {
      next if $sub->covered;
      print "Uncovered subroutine ", $sub->name, " at $file line $location\n";
    }
  }
}

sub print_pod ($db, $file, $) {
  my $pod = $db->cover->file($file)->pod or return;

  for my $location (sort { $a <=> $b } $pod->items) {
    for my $p ($pod->location($location)->@*) {
      next if $p->covered;
      print "Uncovered pod at $file line $location\n";
    }
  }
}

sub report ($pkg, $db, $options) {
  for my $file ($options->{file}->@*) {
    if ($db->cover->file($file)->{meta}{uncompiled}) {
      print "Untested file at $file line 1\n";
      next;
    }
    print_statement($db, $file, $options)   if $options->{show}{statement};
    print_branches($db, $file, $options)    if $options->{show}{branch};
    print_conditions($db, $file, $options)  if $options->{show}{condition};
    print_mcdc($db, $file, $options)        if $options->{show}{mcdc};
    print_subroutines($db, $file, $options) if $options->{show}{subroutine};
    print_pod($db, $file, $options)         if $options->{show}{pod};
  }
}

1

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Report::Compilation - backend for Devel::Cover

=head1 SYNOPSIS

 cover -report compilation

=head1 DESCRIPTION

This module provides a textual reporting mechanism for coverage data. It is
designed to be called from the C<cover> program.

It produces one report per line, in a format like Perl's own compilation error
messages. This makes it easy to use with development tools that understand
compilation output formats, such as Emacs compilation mode, vim quickfix, or IDE
error navigation features.

=head1 OUTPUT FORMAT

The compilation report generates output in the following formats:

=over 4

=item * Statements

  Uncovered statement at filename.pm line 42:

=item * Branches

  Branch never true at filename.pm line 15: condition
  Branch never false at filename.pm line 20: unless condition
  Branch never reached at filename.pm line 25: condition

=item * Conditions

  Uncovered condition (left, right) at filename.pm line 30: expr && expr

=item * MC/DC

  Uncovered MC/DC pair ($q) at filename.pm line 22: $p || $q

=item * Subroutines

  Uncovered subroutine function_name at filename.pm line 50

=item * POD Documentation

  Uncovered pod at filename.pm line 60

=back

=head1 USAGE WITH DEVELOPMENT TOOLS

=head2 Emacs Compilation Mode

To use with Emacs compilation mode:

  M-x compile
  cover -report compilation

Then use C-x ` (next-error) to jump to each uncovered location.

=head2 Vim Quickfix

To use with vim quickfix:

  :cgetexpr system('cover -report compilation')
  :copen

Then use :cn and :cp to navigate between uncovered locations.

=head1 COVERAGE TYPES

The compilation report supports all standard Devel::Cover coverage types:

=over 4

=item * B<statement> - Individual Perl statements

=item * B<branch> - Conditional branch execution paths

=item * B<condition> - Boolean condition combinations

=item * B<mcdc> - Modified condition/decision coverage pairs

=item * B<subroutine> - Subroutine call coverage

=item * B<pod> - POD documentation coverage

=back

Use the standard C<cover> command options to select which types to report:

  cover -report compilation +statement +branch +condition +mcdc +subroutine +pod

=head1 FUNCTIONS

=head2 print_statement ($db, $file, $options)

Prints uncovered statement coverage information for the specified file. Outputs
one line per uncovered statement in the format:

  "Uncovered statement at $file line $line_number:"

=head2 print_branches ($db, $file, $options)

Prints uncovered branch coverage information for the specified file. Reports
branches where one or both execution paths were not taken. Outputs detailed
information about which branch condition was never true, false, or reached.

=head2 print_conditions ($db, $file, $options)

Prints uncovered condition coverage information for the specified file. Reports
logical conditions that were not fully exercised, showing which parts of complex
boolean expressions were not tested.

=head2 print_mcdc ($db, $file, $options)

Prints uncovered MC/DC pair information for the specified file.  Reports each
decision whose independence pairs were not all observed, listing the atomic
conditions whose pair is missing.

=head2 print_subroutines ($db, $file, $options)

Prints uncovered subroutine coverage information for the specified file. Reports
subroutines that were never called during testing.

=head2 print_pod ($db, $file, $options)

Prints uncovered POD (Plain Old Documentation) coverage information for the
specified file. Reports sections of POD documentation that do not have
corresponding tested code.

=head2 report ($pkg, $db, $options)

Main entry point for generating compilation-style coverage reports. Iterates
through all files and calls the appropriate print functions based on the
coverage types requested in the options.

=head1 SEE ALSO

 Devel::Cover

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

2006-09-14 Denis Howe.  Cloned from 0.59 Text.pm and hacked to give a minimal
output in a format similar to that output by Perl itself so that it's easier to
step through the untested locations with Emacs compilation mode.  Copyright
assigned to Paul Johnson.

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

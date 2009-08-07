# Things to add to existing module
package Devel::Cover::DB::Criterion;
use Devel::Cover::Truth_Table;
use strict;
use warnings;

#-------------------------------------------------------------------------------
# Subroutine : error()
# Purpose    : Determine if any of the entries for a given metric type
#              of a line of code are missing full coverage.
# Notes      :
#-------------------------------------------------------------------------------
sub error {
	my $self = shift;
	my $line = shift;
	foreach my $c (@{$self->get($line)}) {
		return 1 if $c->error;
	}
	return;
}


#-------------------------------------------------------------------------------
# Subroutine : branch_coverage()
# Purpose    : Generate textual representation of branches with/without
#              coverage.
# Notes      :
#-------------------------------------------------------------------------------
sub branch_coverage {
	my $self = shift;
	my $line = shift;
	my @txt;
	foreach my $c (@{$self->get($line)}) {
		push @txt, ($c->[0][0] ? ' T ' : '---') .
		           ($c->[0][1] ? ' F ' : '---');
	}
	return @txt;
}


#-------------------------------------------------------------------------------
# Subroutine : truth_table()
# Purpose    : Generate truth table(s) for conditional expressions on a line.
# Notes      :
#-------------------------------------------------------------------------------
sub truth_table {
	my $self = shift;
	my $line = shift;
	my $c = $self->get($line);

        return if @$c > 16;  # Too big - can't get any useful info anyway.

	my @lops;
	foreach my $c (@$c) {
		my $op = $c->[1]{type};
		my @hit = map {defined() && $_ > 0 ? 1 : 0} @{$c->[0]};
		@hit = reverse @hit if $op =~ /^or_[23]$/;
		my $t = {
			tt   => Devel::Cover::Truth_Table->new_primitive($op, @hit),
			cvg  => $c->[1],
			expr => join(' ', @{$c->[1]}{qw/left op right/}),
		};
		push(@lops, $t);
	}
	return map {[$_->{tt}->sort, $_->{expr}]} merge_lineops(@lops);
}


#-------------------------------------------------------------------------------
# Subroutine : merge_lineops()
# Purpose    : Merge multiple conditional expressions into composite
#              truth table(s).
# Notes      :
#-------------------------------------------------------------------------------
sub merge_lineops {
	my @ops = @_;
	my $rotations;
	while ($#ops > 0) {
		my $rm;
		for (1 .. $#ops) {
			if ($ops[0]{expr} eq $ops[$_]{cvg}{left}) {
				$ops[$_]{tt}->left_merge($ops[0]{tt});
				$ops[0] = $ops[$_];
				$rm = $_; last;
			}
			elsif ($ops[0]{expr} eq $ops[$_]{cvg}{right}) {
				$ops[$_]{tt}->right_merge($ops[0]{tt});
				$ops[0] = $ops[$_];
				$rm = $_; last;
			}
			elsif ($ops[$_]{expr} eq $ops[0]{cvg}{left}) {
				$ops[0]{tt}->left_merge($ops[$_]{tt});
				$rm = $_; last;
			}
			elsif ($ops[$_]{expr} eq $ops[0]{cvg}{right}) {
				$ops[0]{tt}->right_merge($ops[$_]{tt});
				$rm = $_; last;
			}
		}
		if ($rm) {
			splice(@ops, $rm, 1);
			$rotations = 0;
		}
		else {
			# First op didn't merge with anything. Rotate @ops in hopes
			# of finding something that can be merged.
			unshift(@ops, pop @ops);

			# Hmm... we've come full circle and *still* haven't found
			# anything to merge. Did the source code have multiple
			# statements on the same line?
			last if ($rotations++ > $#ops);
		}
	}
	return @ops;
}


package Devel::Cover::Truth_Table::Row;
use warnings;
use strict;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my @args = @_;
        # use Data::Dumper; print Dumper \@args;
	return bless {
		inputs    => $args[0],
		result    => $args[1],
		covered   => $args[2],
		criterion => $args[2],
	}, $class;
}

sub inputs {
	my $self = shift;
	return @{$self->{inputs}};
}

sub leftcol {
	my $self = shift;
	return $self->{inputs}[0];
}

sub rightcol {
	my $self = shift;
	return $self->{inputs}[-1];
}

sub leftelems {
	my $self = shift;
	my $n = $#{$self->{inputs}};
	return @{$self->{inputs}}[0 .. $n - 1];
}

sub rightelems {
	my $self = shift;
	my $n = $#{$self->{inputs}};
	return @{$self->{inputs}}[1 .. $n];
}

sub string {
	return "@{$_[0]{inputs}}";
}

sub result {
	return $_[0]{result};
}

sub covered {
	return $_[0]{covered};
}

sub error {
        return 1;
	return $_[0]{error}[$_[1]];
}

package Devel::Cover::Truth_Table;
use warnings;
use strict;
our $VERSION = "0.65";

#-------------------------------------------------------------------------------
# Subroutine : new()
# Purpose    : Create a new Truth_Table object.
# Notes      : Probably best to keep usage of this internal...
#-------------------------------------------------------------------------------
sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	return bless [@_], $class;
}


#-------------------------------------------------------------------------------
# Subroutine : new_primitive()
# Purpose    : Create a new Truth_Table object based on one of the built-in
#              primitives.
# Notes      :
#-------------------------------------------------------------------------------
sub new_primitive {
	my ($proto, $type, @coverage) = @_;

	my %table = (
		and_2 => \&boolean_tt,
		and_3 => \&and_tt,
		or_2  => \&boolean_tt,
		or_3  => \&or_tt,
		xor_4 => \&xor_tt,
	);

	return $proto->new($table{$type}->(@coverage));
}


#-------------------------------------------------------------------------------
# Subroutine : error()
# Purpose    : Determine if a table is missing full coverage.
# Notes      :
#-------------------------------------------------------------------------------
sub error {
    my $self = shift;
    if (@_) { print "[[[", $self->[shift]->error, "]]]\n"; die }
    return $self->[shift]->error if @_;
	foreach (@$self) {
	    return 1 if $_->error;
	}
    return;
}


#-------------------------------------------------------------------------------
# Subroutine : percentage()
# Purpose    : Determine the coverage proportion for a truth table.
# Notes      : Don't care states (X) count as one path, not two.
#-------------------------------------------------------------------------------
sub percentage {
	my $self = shift;
	my ($p, $c) = (scalar @$self, 0);
	foreach (@$self) {
		$c++ if $_->covered;
	}
	return ($c == $p) ? 100 : 100 * $c / $p;
}


# Basic truth table constructors
# Construct a new truth table for 'A <op> B' coverage listing
# primitives. More complicated tables are constructed by merging
# primitives. Each array element represents a row from a truth table,
# divided into two parts;
#   * the input states: 0/1/X (X = don't care)
#   * the output state and a flag to show whether that path has been
#     hit.
# e.g. for the source '$a && $b', and_tt(1,0,1) generates this table:
#
#      $a | $b | $a && $b | covered
#     ----|----|----------|--------
#       0 |  X |    0     |    1
#       1 |  0 |    0     |    0
#       1 |  1 |    1     |    1
#
sub and_tt {
	return(Devel::Cover::Truth_Table::Row->new([0, 'X'], 0, shift),
           Devel::Cover::Truth_Table::Row->new([1,  0 ], 0, shift),
           Devel::Cover::Truth_Table::Row->new([1,  1 ], 1, shift));
}
sub or_tt {
	return(Devel::Cover::Truth_Table::Row->new([0,  0 ], 0, shift),
	       Devel::Cover::Truth_Table::Row->new([0,  1 ], 1, shift),
	       Devel::Cover::Truth_Table::Row->new([1, 'X'], 1, shift));
}
sub xor_tt {
	return(Devel::Cover::Truth_Table::Row->new([0, 0], 0, shift),
	       Devel::Cover::Truth_Table::Row->new([0, 1], 1, shift),
	       Devel::Cover::Truth_Table::Row->new([1, 0], 1, shift),
	       Devel::Cover::Truth_Table::Row->new([1, 1], 0, shift));
}
sub boolean_tt {
	return(Devel::Cover::Truth_Table::Row->new([0], 0, shift),
	       Devel::Cover::Truth_Table::Row->new([1], 1, shift));
}


#-------------------------------------------------------------------------------
# Subroutine : sort()
# Purpose    : Sort a truth table
# Notes      :
#-------------------------------------------------------------------------------
sub sort {
	my $self = shift;
	@$self = sort {$a->string cmp $b->string} @$self;
	return $self;
}


#sub rows {return @{$_[0]}}


#-------------------------------------------------------------------------------
# Subroutine : text()
# Purpose    : Formatted text representation of a truth table
# Notes      :
#-------------------------------------------------------------------------------
sub text {
	my $self = shift;
	my $h = 'A';
	my @h = map {$h++} ($self->[0]->inputs);
	my $hdr = "@h |exp|hit";
	my @text;
	push @text, $hdr, '-' x length($hdr);
	foreach (@$self) {
		push @text, sprintf("%s | %s |%s", $_->string(),
			$_->result(), $_->covered() ? '+++' : '---');
	}
	push @text, '-' x length($hdr);
	return @text;
}


#-------------------------------------------------------------------------------
# Subroutine : html()
# Purpose    : HTML representation of a truth table
# Notes      :
#-------------------------------------------------------------------------------
sub html {
	my $self  = shift;
	my @class = (shift || 'uncovered', shift || 'covered');
	my $html  = "<table><tr>";
	my $h     = 'A';
	for ($self->[0]->inputs) {
		$html .= "<th>$h</th>";
		$h++;
	}
	$html .= "<th>dec</th></tr>";

        my $c = 0;
	foreach (@$self) {
		my $class = $class[!$_->error($c++) || $_->covered];
		$html .= qq'<tr align="center"><td class="$class">';
		$html .= join(qq'</td><td class="$class">', $_->inputs, $_->result);
		$html .= "</td></tr>";
	}
	$html .= "</table>";
	return $html;
}


# Truth table merge routines:
# Combine simple truth tables into more complicated ones.
#
# Given two truth tables, A and B, such that
#    A is the truth table for the expression 'a1 <op> a2'
#    B is the truth table for the expression 'b1 <op> b2'
#    b1 = 'a1 <op> a2'
#
# We want to merge the contents of A into B creating a new, larger truth
# table for the composite expression '(a1 <op> a2) <op> b2'. We do this
# by replacing elements of B corresponding to b1 with (all) the inputs
# to A where the result of A matches the element removed from B. e.g.
#
#    A => a1 || a2        B => b1 && b2
#    a1 a2 | a1 || a2     b1 b2 | b1 && b2
#    ----------------     ----------------
#    0  0  |    0         0  X  |    0
#    0  1  |    1         1  0  |    0
#    1  X  |    1         1  1  |    1
#
# For the first row of B, b1 = 0. We replace this with the all the
# (a1,a2) values where the expression 'a1 || a2' = 0. In this case, just
# (0,0). Thus, the first row of our new table becomes (0,0,X).
#
# In the second row of B, b1 = 1. Thus, from A we add rows for A values
# (0,1) and (1,X) along with the value for b2 (0). Repeat the process
# for the final row of B where b2 = 1. The resulting truth table is:
#
#    a1 a2 b2 | (a1 || a2) && b2
#    ---------------------------
#    0  0  X  |        0
#    0  1  0  |        0
#    1  X  0  |        0
#    0  1  1  |        1
#    1  X  1  |        1
#
# Note that we don't have to calulate the result, it's taken directly
# from table B. We can do this because we've replaced b1 with an
# something that evaluates to the same thing.
#
# This is a "left merge" because we merged A into the leftmost column of
# B. We can also do a "right merge" where we place A into the rightmost
# column of B. (This is what we would have done if we had had
# b2 = 'a1 <op> a2' instead of b1.)
#
# Finally, merging the truth tables isn't much use if we don't work out
# which paths have been covered. We haven't shown it, but each row of
# the truth tables also contains a "covered" boolean. The value of this
# in the merged table is the AND'd values from the input tables A and B.
# In the case where all the inputs from B are 'X' it is simply the
# value from table A.

#-------------------------------------------------------------------------------
# Subroutine : right_merge(\@,\@)
# Purpose    : Merge truth table 2 into the rightmost column of truth table 1.
# Notes      :
#-------------------------------------------------------------------------------
sub right_merge {
	my ($tt1, $tt2) = @_;

	# find the rows of tt2 that have a result of false/true
	my @merge = ([grep {! $_->result} @$tt2], [grep {$_->result} @$tt2]);
	# if the rightmost column of tt1 is 'X', we don't care what the
	# input from tt2 was
	my @dontcare = map {'X'} $tt2->[0]->inputs;

	my @tt;
	foreach my $row1 (@$tt1) {
		if ($row1->rightcol eq 'X') {
			push(@tt, Devel::Cover::Truth_Table::Row->new([$row1->leftelems, @dontcare],
				$row1->result, $row1->covered));
		}
		else {
			# expand value from tt1 with rows from tt2 that result in
			# that value
			foreach my $row2 (@{$merge[$row1->rightcol]}) {
				push(@tt, Devel::Cover::Truth_Table::Row->new([$row1->leftelems, $row2->inputs],
					$row1->result, $row1->covered && $row2->covered));
			}
		}
	}
	$_[0] = $tt2->new(@tt);
}

#-------------------------------------------------------------------------------
# Subroutine : left_merge(\@,\@)
# Purpose    : Merge truth table 2 into the leftmost column of truth table 1.
# Notes      :
#-------------------------------------------------------------------------------
sub left_merge {
	my ($tt1, $tt2) = @_;

	# find the rows of tt2 that have a result of false/true
	my @merge = ([grep {! $_->result} @$tt2], [grep {$_->result} @$tt2]);

	my @tt;
	foreach my $row1 (@$tt1) {
		my $rightmatters  = grep {$_ ne 'X'} $row1->rightelems;
		foreach my $row2 (@{$merge[$row1->leftcol]}) {
			# expand value from tt1 with rows from tt2 that result in
			# that value
			push(@tt, Devel::Cover::Truth_Table::Row->new([$row2->inputs, $row1->rightelems],
				$row1->result,
				($rightmatters) ? $row1->covered && $row2->covered : $row2->covered));
		}
	}
	$_[0] = $tt2->new(@tt);
}

1;

=pod

=head1 NAME

Devel::Cover::Truth_Table - Create and manipulate truth tables for
coverage objects.

=head1 SYNOPSIS

  use Devel::Cover::Truth_Table;

  # $a || $b
  my $or_tt  = Devel::Cover::Truth_Table->new_primitive('or_3', 0, 1, 1);

  # $c && $d
  my $and_tt = Devel::Cover::Truth_Table->new_primitive('and_3', 1, 0, 1);

  # merge contents of $and_tt into right column of $or_tt, to create
  # $a || ($c && $d)
  $or_tt->right_merge($and_tt);

  # get a (sorted) textual representation
  my @text = $or_tt->sort->text;
  print "$_\n" foreach @text;

  __END__
  A B C |exp|hit
  --------------
  0 0 X | 0 |---
  0 1 0 | 0 |---
  0 1 1 | 1 |+++
  1 X X | 1 |+++
  --------------

=head1 DESCRIPTION

This module provides methods for creating and merging conditional
primitives (C<$a && $b>, C<$c || $d>, etc.) into more complex composite
expressions.

=head1 METHODS

=head2 new_primitive($op, @coverage)

Create a new truth table based on one of the built-in primitives, which
are the subclasses of Devel::Cover::DB::Condition. C<$op> is one of the
following:

=over 4

=item and_3

C<and> or C<&&> with three conditional paths.

=item or_3

C<or> or C<||> with three conditional paths.

=item or_2

C<or> or C<||> with two conditional paths. (i.e., when the right hand
side of the expression is a constant)

=item xor_4

C<xor> with four conditional paths.

=back

C<@coverage> is a list booleans identifying which of the possible paths
have been covered.

=head2 sort()

Sorts a truth table (in place) and returns the sorted object.

=head2 text()

Format a truth table to an array of strings for printing.

=head2 html()

Format a truth table in HTML.

=head2 error()

=head2 percentage()

Determines the proportion of possible conditions that have coverage.

=head2 right_merge($sub_table)

Merge entries from C<$sub_table> into right column of table.

=head2 left_merge($sub_table)

Merge entries from C<$sub_table> into left column of table.

=head1 SEE ALSO

Devel::Cover

=head1 BUGS

None that I'm aware of...

=head1 VERSION

Version 0.65 - 8th August 2009

=head1 LICENSE

Copyright 2002 Michael Carman <mjcarman@mchsi.com>

This software is free. It is licensed under the same terms as Perl
itself. The latest version should be available from: http://www.pjcj.net

=cut

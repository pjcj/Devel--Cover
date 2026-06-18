# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Condition_table;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

package Devel::Cover::Condition_table::Row {

  sub new ($class, %args) {
    bless \%args, $class
  }

  sub inputs      ($self) { $self->{inputs} }
  sub result      ($self) { $self->{result} }
  sub covered     ($self) { $self->{covered} }
  sub uncoverable ($self) { $self->{uncoverable} }
}

package Devel::Cover::Condition_table::Table {

  sub new ($class, %args) {
    bless \%args, $class
  }

  sub expr       ($self) { $self->{expr} }
  sub short_expr ($self) { $self->{short_expr} }
  sub labels     ($self) { $self->{labels}->@* }
  sub rows       ($self) { $self->{rows}->@* }

  # True unless the rows are an unverified synthesis: a compound decision
  # (>= 3 atomics, so >= 2 logops) with no observed vectors.  Its row coverage
  # is a cross-product whose co-occurrence was never demonstrated, so neither
  # MC/DC nor the truth-table display may treat those rows as covered.  A single
  # logop is exact from its hit counts, and observed vectors are real.
  sub proven ($self) { $self->{proven} }
}

package Devel::Cover::Condition_table;

# Truth table specs: each entry is [inputs, result].
my @Boolean_spec = ([[0], 0], [[1], 1]);
my @And3_spec    = ([[0, "X"], 0], [[1, 0], 0], [[1, 1], 1]);
my @Or3_spec     = ([[1, "X"], 1], [[0, 1], 1], [[0, 0], 0]);
my @Xor4_spec    = ([[0, 0], 0], [[0, 1], 1], [[1, 0], 1], [[1, 1], 0]);

my %Primitive = (
  and_2 => \@Boolean_spec,
  and_3 => \@And3_spec,
  or_2  => \@Boolean_spec,
  or_3  => \@Or3_spec,
  xor_4 => \@Xor4_spec,
);

my %Is_boolean = (and_2 => 1, or_2 => 1);

sub _hits ($condition) {
  map { defined && $_ > 0 ? 1 : 0 } $condition->[0]->@*
}

sub _make_rows ($spec, $hits, $unc) {
  my @hits = @$hits;
  my @unc  = @$unc;
  map {
    Devel::Cover::Condition_table::Row->new(
      inputs      => $_->[0],
      result      => $_->[1],
      covered     => shift @hits,
      uncoverable => shift @unc,
    )
  } @$spec
}

# Per-spec-row uncoverable flags from the condition's "# uncoverable condition"
# markers, which align positionally with the outcome (and so spec-row) order.
sub _uncov ($condition) {
  map $_ ? 1 : 0, ($condition->[2] // [])->@*
}

sub _expr ($condition) {
  join " ", $condition->[1]->@{qw( left op right )}
}

# Each expansion is [inputs, covered, uncoverable].  A leaf operand or a
# short-circuited (X) operand contributes no sub-decision row, so it is never
# uncoverable in its own right.
sub _expand_operand ($val, $sub_rows, $negated = 0) {
  unless ($sub_rows) {
    return ([[$val], 1, 0])
  }
  if ($val eq "X") {
    my $width = $sub_rows->[0]->inputs->@*;
    return ([[("X") x $width], 1, 0])
  }
  my $match = $negated ? 1 - $val : $val;
  map { [$_->inputs, $_->covered, $_->uncoverable] } grep {
    $_->result == $match
  } @$sub_rows
}

# A logop recorded in void context collapses to its boolean 2-count form, but
# the recorded structure keeps both operands.  Promote a void-collapsed node
# back to its 3-count form so MC/DC rebuilds the full decision; the rebuilt
# table has no observed vectors and so is reported unproven (honest 0%, never a
# false pass).  A const-right collapse is a real boolean and is left alone.
sub _effective_type ($condition) {
  my $info = $condition->[1];
  my $type = $info->{type};
  $type =~ s/_2\z/_3/ if $info->{void_collapsed};
  $type
}

sub _resolve_children ($condition, $find) {
  my $info       = $condition->[1];
  my $left_cond  = $find->($info->{left_addr},  $info->{left});
  my $right_cond = $find->($info->{right_addr}, $info->{right});
  ($info, $left_cond, $right_cond)
}

sub _build_rows ($condition, $find) {
  my $type = _effective_type($condition);
  my $spec = $Primitive{$type} or return;

  my ($info, $left_cond, $right_cond) = _resolve_children($condition, $find);

  # This operator's own per-outcome uncoverable markers map positionally onto
  # its spec rows, and propagate to the combined rows expanded from them below.
  my @hits = _hits($condition);
  my @prim = _make_rows($spec, \@hits, [_uncov($condition)]);

  my $left_rows  = $left_cond  ? [_build_rows($left_cond,  $find)] : undef;
  my $right_rows = $right_cond ? [_build_rows($right_cond, $find)] : undef;

  my $left_neg  = $info->{left_negated}  || 0;
  my $right_neg = $info->{right_negated} || 0;

  my @rows;

  for my $row (@prim) {
    my @inputs = $row->inputs->@*;
    if (@inputs == 1) {
      my @left_exp = _expand_operand($inputs[0], $left_rows, $left_neg);
      for my $le (@left_exp) {
        push @rows,
          Devel::Cover::Condition_table::Row->new(
            inputs      => $le->[0],
            result      => $row->result,
            covered     => $row->covered && $le->[1],
            uncoverable => $row->uncoverable || $le->[2],
          );
      }
    } else {
      my @left_exp  = _expand_operand($inputs[0], $left_rows,  $left_neg);
      my @right_exp = _expand_operand($inputs[1], $right_rows, $right_neg);
      for my $le (@left_exp) {
        for my $re (@right_exp) {
          push @rows,
            Devel::Cover::Condition_table::Row->new(
              inputs      => [$le->[0]->@*, $re->[0]->@*],
              result      => $row->result,
              covered     => $row->covered && $le->[1] && $re->[1],
              uncoverable => $row->uncoverable || $le->[2] || $re->[2],
            );
        }
      }
    }
  }
  @rows
}

sub _build_short_expr ($condition, $find, $counter) {
  my ($info, $left_cond, $right_cond) = _resolve_children($condition, $find);
  my $type = _effective_type($condition);

  my $left
    = $left_cond
    ? _build_short_expr($left_cond, $find, $counter)
    : chr ord("A") + $$counter++;
  $left = "not($left)" if $info->{left_negated};

  return $left if $Is_boolean{$type};

  my $right
    = $right_cond
    ? _build_short_expr($right_cond, $find, $counter)
    : chr ord("A") + $$counter++;
  $right = "not($right)" if $info->{right_negated};
  "$left $info->{op} $right"
}

sub _build_labels ($condition, $find) {
  my ($info, $left_cond, $right_cond) = _resolve_children($condition, $find);
  my $type = _effective_type($condition);

  my @labels;

  push @labels, $left_cond ? _build_labels($left_cond, $find) : $info->{left};
  push @labels, $right_cond ? _build_labels($right_cond, $find) : $info->{right}
    unless $Is_boolean{$type};
  @labels
}

# Observed-vector data overrides synthesis: rows are covered iff their input
# vector matches an observed key.  Synthesised rows not in the observed set stay
# rendered with covered=0 so the truth table still draws.
#
# A constant right operand (e.g. `$x // {}`) collapses the table to fewer inputs
# than the runtime recorded for the uncollapsed expression, so an observed
# vector can carry more columns than a row.  The collapse always drops the
# trailing right operand, leaving the left subtree, so project each observed
# vector onto the surviving leading columns before matching.  When the
# dimensions already agree the projection is a no-op.
#
# Operates on the row's `inputs` arrayref and `covered` slots, so it serves both
# this module's rows and the Truth_Table reporters' rows, which share that
# layout.
sub apply_observed_vectors ($rows, $obs) {
  my $width = @$rows ? $rows->[0]{inputs}->@* : 0;
  my %seen;
  for my $key (keys %$obs) {
    next unless $obs->{$key};
    my @v = split /\|/, $key, -1;
    $seen{ join "|", @v[0 .. $width - 1] } = 1;
  }
  $_->{covered} = $seen{ join "|", $_->{inputs}->@* } ? 1 : 0 for @$rows;
}

sub for_line ($class, $conditions, $observed = undef) {
  return if @$conditions > 16;

  my %expr_map;
  $expr_map{ _expr($_) } = $_ for @$conditions;

  my %addr_map;
  for my $c (@$conditions) {
    my $a = $c->[1]{addr};
    $addr_map{$a} = $c if defined $a;
  }

  # Prefer addr-based lookup, fall back to string matching
  my $find = sub ($addr, $str) {
    (defined $addr && $addr_map{$addr}) || $expr_map{$str}
  };

  # Find roots: conditions not referenced as another's operand
  my %is_child;
  for my $c (@$conditions) {
    my $info = $c->[1];
    for my $side (qw( left right )) {
      my $found = $find->($info->{"${side}_addr"}, $info->{$side});
      $is_child{ _expr($found) } = 1 if $found;
    }
  }

  my @tables;
  for my $i (0 .. $#$conditions) {
    my $c = $conditions->[$i];
    next if $is_child{ _expr($c) };

    my @rows    = _build_rows($c, $find);
    my @labels  = _build_labels($c, $find);
    my $obs     = $observed && $observed->[$i];
    my $applied = $obs      && %$obs ? 1 : 0;

    apply_observed_vectors(\@rows, $obs) if $applied;

    my $counter = 0;
    push @tables,
      Devel::Cover::Condition_table::Table->new(
        expr       => _expr($c),
        short_expr => _build_short_expr($c, $find, \$counter),
        labels     => \@labels,
        rows       => \@rows,
        proven     => @labels < 3 || $applied ? 1 : 0,
      );
  }
  @tables
}

1

__END__

=pod

=encoding utf8

=head1 NAME

Devel::Cover::Condition_table - Condition truth tables for coverage
reporting.

=head1 SYNOPSIS

  use Devel::Cover::Condition_table;

  my @tables = Devel::Cover::Condition_table->for_line(\@conditions);
  for my $table (@tables) {
    say $table->expr;
    for my $row ($table->rows) {
      say join " ", @{$row->inputs}, "|", $row->result, $row->covered;
    }
  }

=head1 DESCRIPTION

Generates condition truth tables from Devel::Cover condition data.
Takes the array of Condition_* objects for a source line and returns
one Table per expression, each containing rows with input combinations,
expected results, and coverage status.

=head1 METHODS

=head2 for_line ($conditions)

Class method. Takes an arrayref of condition objects for a line.
Returns a list of Table objects.

=head1 SEE ALSO

L<Devel::Cover>

=head1 LICENCE

Copyright 2026, Paul Johnson (paul@pjcj.net)

This software is free. It is licensed under the same terms as Perl
itself. The latest version should be available from: https://pjcj.net

=cut

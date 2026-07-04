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

use Devel::Cover::Log qw( dcwarn );

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
  sub proven     ($self) { $self->{proven} }
  sub too_wide   ($self) { $self->{too_wide} }
}

package Devel::Cover::Condition_table;

# Truth table specs: each entry is [inputs, result], in stored hit order
# (the Condition_*::headers order).
my @And2_spec = ([[0], 0], [[1], 1]);
my @Or2_spec  = ([[1], 1], [[0], 0]);
my @And3_spec = ([[0, "X"], 0], [[1, 0], 0], [[1, 1], 1]);
my @Or3_spec  = ([[1, "X"], 1], [[0, 1], 1], [[0, 0], 0]);
my @Xor4_spec = ([[1, 1], 0], [[1, 0], 1], [[0, 1], 1], [[0, 0], 0]);

my %Primitive = (
  and_2 => \@And2_spec,
  and_3 => \@And3_spec,
  or_2  => \@Or2_spec,
  or_3  => \@Or3_spec,
  xor_4 => \@Xor4_spec,
);

my %Is_boolean = (and_2 => 1, or_2 => 1);

# Per-decision analysis limit; matches DC_MAX_DECISION_WIDTH in Cover.xs
my $Max_width = 16;

sub max_width ($class) { $Max_width }

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

# Uncoverable flags align positionally with the outcome (spec-row) order
sub _uncov ($condition) {
  map $_ ? 1 : 0, ($condition->[2] // [])->@*
}

sub _expr ($condition) {
  join " ", $condition->[1]->@{qw( left op right )}
}

# Each expansion is [inputs, covered, uncoverable]
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

# Promote a void-collapsed logop back to its 3-count form (see DESCRIPTION)
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

sub apply_observed_vectors ($rows, $obs, $expr = undef) {
  my $width = @$rows ? $rows->[0]{inputs}->@* : 0;
  my %seen;
  for my $key (sort keys %$obs) {
    next unless $obs->{$key};
    my @v = split /\|/, $key, -1;
    if (@v < $width) {
      # Narrower than the rows: the recorder and the table disagreed
      dcwarn qq(Ignoring short MC/DC vector "$key")
        . (defined $expr ? " for $expr" : "");
      next;
    }
    $seen{ join "|", @v[0 .. $width - 1] } = 1;
  }
  $_->{covered} = $seen{ join "|", $_->{inputs}->@* } ? 1 : 0 for @$rows;
}

sub for_line ($class, $conditions, $observed = undef) {
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

    my @labels = _build_labels($c, $find);
    if (@labels > $Max_width) {
      push @tables,
        Devel::Cover::Condition_table::Table->new(
          expr     => _expr($c),
          labels   => \@labels,
          rows     => [],
          proven   => 0,
          too_wide => 1,
        );
      next;
    }

    my @rows    = _build_rows($c, $find);
    my $obs     = $observed && $observed->[$i];
    my $applied = $obs      && %$obs ? 1 : 0;

    apply_observed_vectors(\@rows, $obs, _expr($c)) if $applied;

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

"
Flood the world deep in sunlight
Break into the peaceful wild
"

__END__

=pod

=encoding utf8

=head1 NAME

Devel::Cover::Condition_table - Condition truth tables for coverage reporting.

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

Generates condition truth tables from Devel::Cover condition data. Takes the
array of Condition_* objects for a source line and returns one Table per
decision, each containing rows with input combinations, expected results, and
coverage status.

Rows are synthesised from each operator's recorded hit counts.  A compound
decision (two or more logops) is synthesised as a cross-product of its operands'
rows, so a combined row can appear covered although its inputs never occurred
together in one execution. Two mechanisms keep that honest: observed input
vectors, recorded at runtime for MC/DC, override synthesis when supplied (see
L</apply_observed_vectors ($rows, $obs, $expr)>), and a table whose rows remain
an unverified synthesis is marked unproven (see L</proven>).

A logop executed in void context is recorded collapsed to its boolean 2-count
form, but the recorded structure keeps both operands.  Such a node is promoted
back to its 3-count form so MC/DC rebuilds the full decision; the rebuilt table
has no observed vectors and so is reported unproven - an honest 0%, never a
false pass.  A constant-right collapse is a real boolean and is left alone.

=head1 ROW OBJECTS

Each table row is a C<Devel::Cover::Condition_table::Row>, constructed by C<new
(%args)> with read-only accessors:

=over

=item inputs

Arrayref of column values: C<0>, C<1>, or C<"X"> for an operand never evaluated
because an earlier operand short-circuited.

=item result

The decision's outcome for these inputs.

=item covered

True if this input combination was exercised.

=item uncoverable

True if this row is excused by an C<# uncoverable condition> marker.

=back

=head1 TABLE OBJECTS

L</for_line ($conditions, $observed)> returns
C<Devel::Cover::Condition_table::Table> objects, constructed by C<new (%args)>
with read-only accessors:

=over

=item expr

The decision's source text.

=item short_expr

The decision with each atomic condition replaced by a letter (A, B, ...), as
displayed above rendered truth tables.

=item labels

The atomic condition texts, one per column, in depth-first left-to-right order.

=item rows

The Row objects.

=item proven

True unless the rows are an unverified synthesis: a compound decision (three or
more atomics, so two or more logops) with no observed vectors.  Its row coverage
is a cross-product whose co-occurrence was never demonstrated, so neither MC/DC
nor the truth-table display may treat those rows as covered.  A single logop is
exact from its hit counts, and observed vectors are real.

=item too_wide

True for the stub table of a decision wider than the analysis limit: it carries
the expression and labels but no rows.

=back

=head1 METHODS

=head2 max_width

Class method.  The per-decision analysis limit of 16 atomic conditions, matching
C<DC_MAX_DECISION_WIDTH> in the XS recorder.

=head2 apply_observed_vectors ($rows, $obs, $expr)

Overrides synthesised coverage with observed data: each row in C<$rows> is
covered iff its input vector matches a key of C<$obs>. Synthesised rows not in
the observed set stay rendered with C<covered=0> so the truth table still draws.

A constant right operand (e.g. C<$x // {}>) collapses the table to fewer inputs
than the runtime recorded for the uncollapsed expression, so an observed vector
can carry more columns than a row.  The collapse always drops the trailing right
operand, leaving the left subtree, so each observed vector is projected onto the
surviving leading columns before matching; when the dimensions already agree the
projection is a no-op.  A vector narrower than the rows means the recorder and
the table disagreed about columns; such a key is skipped with a warning (named
with C<$expr> when given, suppressed by C<-silent>) rather than matching wrong
columns.

Operates on the rows' C<inputs> arrayrefs and C<covered> slots directly, so it
serves both this module's rows and the Truth_Table reporters' rows, which share
that layout.

=head2 for_line ($conditions, $observed)

Class method. Takes an arrayref of condition objects for a line and an optional
arrayref of observed input-vector hashes indexed parallel to the
conditions. Returns a list of Table objects, one per decision on the line.

A decision with more than 16 atomic conditions is not analysed: its Table is a
stub with C<too_wide> true, carrying the expression and labels but no rows.

=head1 SEE ALSO

L<Devel::Cover>

=head1 LICENCE

Copyright 2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself. The
latest version should be available from: https://pjcj.net

=cut

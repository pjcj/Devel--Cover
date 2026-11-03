# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Static;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Scalar::Util qw( refaddr );

my $Have_ppi;

BEGIN { $Have_ppi = eval { require PPI; 1 } }

my %Const_rhs = map { $_ => 1 }
  qw( die warn croak confess next last redo goto return exit exec undef bless );

sub _is_module_true ($doc, $s) {
  # Must be a bare PPI::Statement (not a subclass)
  return 0 unless ref($s) eq "PPI::Statement";

  # Must contain only a single significant token that is a number
  my @tokens = grep !$_->isa("PPI::Token::Whitespace"), $s->children;
  return 0
    unless @tokens == 1
    || ( @tokens == 2
      && $tokens[1]->isa("PPI::Token::Structure")
      && $tokens[1]->content eq ";");
  return 0 unless $tokens[0]->isa("PPI::Token::Number");

  # Must be the last significant statement in the document
  my $next = $s->next_sibling;
  while ($next) {
    return 0 if $next->significant;
    $next = $next->next_sibling;
  }
  1
}

sub _inside_for_parens ($s) {
  my $parent = $s->parent or return 0;
  return 0 unless $parent->isa("PPI::Structure::List");
  my $grandparent = $parent->parent or return 0;
  $grandparent->isa("PPI::Statement::Compound")
}

sub _count_statements ($doc, $includes, $compounds) {
  my $all    = $doc->find("PPI::Statement") || [];
  my $simple = 0;
  for my $s (@$all) {
    next if $s->isa("PPI::Statement::Compound");
    next if $s->isa("PPI::Statement::Sub");
    next if $s->isa("PPI::Statement::Scheduled");
    next if $s->isa("PPI::Statement::Package");
    next if $s->isa("PPI::Statement::Include");
    next if ref($s) eq "PPI::Statement::Expression";
    next if $s->isa("PPI::Statement::Null");
    next if $s->isa("PPI::Statement::Data");
    next if $s->isa("PPI::Statement::End");
    next if _is_module_true($doc, $s);
    next if _inside_for_parens($s);
    $simple++;
  }

  my $compound_headers = @$compounds;
  my $include_stmts    = @$includes * 3;

  $simple + $compound_headers + $include_stmts
}

sub _count_decisions ($node) {
  my $compounds = $node->find("PPI::Statement::Compound") || [];
  my $decisions = 0;
  for my $c (@$compounds) {
    my $type = $c->type // "";
    if ($type =~ /^(?:if|unless)$/) {
      $decisions++;
      my $elsifs = $c->find(sub {
        $_[1]->isa("PPI::Token::Word")
          && $_[1]->content eq "elsif"
          && $_[1]->parent == $c
      }) || [];
      $decisions += @$elsifs;
    }
  }

  # Ternary operators
  my $ternaries = $node->find(sub {
    $_[1]->isa("PPI::Token::Operator") && $_[1]->content eq "?"
  }) || [];
  $decisions += @$ternaries;

  # Statement modifiers: postfix if/unless
  my $modifiers = $node->find(sub {
    return 0 unless $_[1]->isa("PPI::Token::Word");
    my $w = $_[1]->content;
    return 0 unless $w =~ /^(?:if|unless)$/;
    my $p = $_[1]->parent or return 0;
    !$p->isa("PPI::Statement::Compound")
  }) || [];
  $decisions += @$modifiers;

  $decisions
}

sub _count_branches ($doc) {
  _count_decisions($doc) * 2
}

sub _has_const_rhs ($op) {
  my $rhs = $op->snext_sibling or return 0;

  # Keyword: die, warn, next, last, return, etc.
  return 1 if $rhs->isa("PPI::Token::Word") && $Const_rhs{ $rhs->content };

  # String or number literal
  return 1 if $rhs->isa("PPI::Token::Number");
  return 1 if $rhs->isa("PPI::Token::Quote");

  # undef literal (PPI::Token::Word "undef" is already caught above)
  # Reference constructor: \, anonymous arrayref/hashref
  return 1 if $rhs->isa("PPI::Token::Cast") && $rhs->content eq "\\";
  return 1 if $rhs->isa("PPI::Structure::Constructor");

  0
}

sub _logical_ops ($doc) {
  $doc->find(sub {
    $_[1]->isa("PPI::Token::Operator")
      && $_[1]->content =~ m!^(?:&&|\|\||//|&&=|\|\|=|//=|and|or|xor)$!
  }) || []
}

sub _count_conditions ($doc) {
  my $total = 0;

  for my $op (_logical_ops($doc)->@*) {
    my $name = $op->content;
    if ($name eq "xor") {
      $total += 4;
    } elsif (_has_const_rhs($op)) {
      $total += 2;
    } else {
      $total += 3;
    }
  }

  $total
}

sub _count_mcdc ($doc) {
  my %decisions;
  for my $op (_logical_ops($doc)->@*) {
    my $s = $op->statement or next;
    my $d = $decisions{ refaddr $s } //= { ops => 0, const => 0 };
    $d->{ops}++;
    $d->{const}++ if $op->content ne "xor" && _has_const_rhs($op);
  }

  my $total = 0;
  $total += $_->{ops} + 1 - $_->{const} for values %decisions;
  $total
}

sub _count_subroutines ($doc, $includes) {
  my $subs = $doc->find(sub {
    $_[1]->isa("PPI::Statement::Sub") && $_[1]->name
  }) || [];

  @$subs + @$includes
}

sub _count_pod ($doc) {
  my $subs = $doc->find(sub {
    $_[1]->isa("PPI::Statement::Sub")
      && !$_[1]->isa("PPI::Statement::Scheduled")
      && $_[1]->name
  }) || [];
  0 + @$subs
}

sub count_criteria ($file) {
  return unless $Have_ppi;
  my $doc = PPI::Document->new($file) or return;

  my $includes  = $doc->find("PPI::Statement::Include")  || [];
  my $compounds = $doc->find("PPI::Statement::Compound") || [];

  +{
    statement  => _count_statements($doc, $includes, $compounds),
    branch     => _count_branches($doc),
    condition  => _count_conditions($doc),
    mcdc       => _count_mcdc($doc),
    subroutine => _count_subroutines($doc, $includes),
    pod        => _count_pod($doc),
  }
}

sub _count_loops ($node) {
  my $loops = $node->find(sub {
    my $n = $_[1];
    return ($n->type // "") =~ /^(?:while|for|foreach)$/
      if $n->isa("PPI::Statement::Compound");
    return 0 unless $n->isa("PPI::Token::Word");
    return 0 unless $n->content =~ /^(?:for|foreach|while|until)$/;
    my $p = $n->parent or return 0;
    return 0 if $p->isa("PPI::Statement::Compound");
    return 0 if $p->isa("PPI::Statement::Expression");
    my $prev = $n->sprevious_sibling;
    !($prev && $prev->isa("PPI::Token::Operator") && $prev->content eq "->")
  }) || [];
  0 + @$loops
}

sub _count_signature_defaults ($node) {
  my $protos   = $node->find("PPI::Token::Prototype") || [];
  my $defaults = 0;
  for my $proto (@$protos) {
    $defaults += grep m{^\s*\(?\s*\$\w*\s*(?://|\|\|)?=(?![=>])}, split /,/,
      $proto->content;
  }
  $defaults
}

sub _count_cc ($node) {
  _count_decisions($node) + _count_loops($node) + _logical_ops($node)->@*
    + _count_signature_defaults($node)
}

sub _inside_named_sub ($node) {
  while ($node = $node->parent) {
    return 1
      if $node->isa("PPI::Statement::Sub")
      && !$node->isa("PPI::Statement::Scheduled");
  }
  0
}

sub _file_level_line ($doc) {
  my ($first) = grep {
         $_->isa("PPI::Statement")
      && !$_->isa("PPI::Statement::Package")
      && !$_->isa("PPI::Statement::Sub")
  } $doc->schildren;
  $first ? $first->line_number : 1
}

sub per_sub_complexity ($file) {
  return unless $Have_ppi;
  my $doc = PPI::Document->new($file) or return;

  my $named_subs = $doc->find(sub {
    $_[1]->isa("PPI::Statement::Sub")
      && !$_[1]->isa("PPI::Statement::Scheduled")
      && $_[1]->name
  }) || [];

  my @subs;
  my $file_level = _count_cc($doc) + 1;
  for my $sub (@$named_subs) {
    $sub->block or next;
    my $decisions = _count_cc($sub);
    $file_level -= $decisions unless _inside_named_sub($sub);
    push @subs,
      { name => $sub->name, line => $sub->line_number, cc => $decisions + 1 };
  }

  push @subs, {
      name => "{file-level code}",
      line => _file_level_line($doc),
      cc   => $file_level,
    };

  \@subs
}

"
Winter, spring, summer, or fall
All you have to do is call
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Static - PPI-based static analysis for uncovered files

=head1 SYNOPSIS

  use Devel::Cover::Static;

  my $counts = Devel::Cover::Static::count_criteria("lib/Foo.pm");
  # { statement => 12, branch => 4, condition => 2, mcdc => 2,
  #   subroutine => 3, pod => 3 }

=head1 DESCRIPTION

This module provides static analysis of Perl source files using PPI. It
estimates the number of coverable constructs (statements, branches, conditions,
mcdc atomic conditions, subroutines and pod) without executing the code.

It is used by L<Devel::Cover::DB> to populate coverage data for files discovered
via C<--select_dir> that were never exercised by any test. The counts allow
reports to show meaningful 0/N ratios rather than bare zeroes.

Returns C<undef> if PPI is not installed or the file cannot be parsed.

=head1 SUBROUTINES

=over 4

=item count_criteria($file)

Parses C<$file> with PPI and returns a hashref of estimated coverable counts:

  {
    statement  => $n,
    branch     => $n,
    condition  => $n,
    mcdc       => $n,
    subroutine => $n,
    pod        => $n,
  }

Returns C<undef> if PPI is unavailable or the file fails to parse.

B<Statements> include simple statements, compound headers (if/for/while), and an
estimated three markers per C<use>/C<require>. The trailing C<1;> return value
and statements inside for-loop parentheses are excluded.

B<Branches> count two outcomes per decision point: if/unless blocks, elsif
clauses, ternary operators, and postfix if/unless modifiers. Loop conditions are
currently omitted to avoid overcounting.

B<Conditions> count outcomes per logical operator: 4 for C<xor>, 2 when the
right-hand side is a constant or flow-control keyword (matching Devel::Cover's
C<$Const_right> heuristic), and 3 otherwise.

B<Mcdc> counts atomic conditions per decision, treating each statement that
holds logical operators as one decision: operators plus one, less one for each
short-circuit operator whose right-hand side is a constant or flow-control
keyword (its truth table has no atomic condition for that operand). The
estimate is rough in both directions - a decision evaluated in boolean context
builds a narrower table than the source suggests, and a statement holding two
separate decisions is counted as one.

B<Subroutines> count named subs, special blocks such as C<BEGIN> and one
C<BEGIN> per C<use>/C<require>.

B<Pod> counts named subroutines (the number of subs that should have
documentation). It leaves out special blocks such as C<BEGIN>, which
C<Pod::Coverage> never sees.

=item per_sub_complexity($file)

Parses C<$file> with PPI and returns an arrayref of per-subroutine cyclomatic
complexity data:

  [
    { name => "sub_name", line => $n, cc => $cc },
    ...
  ]

The CC of a named subroutine is one plus the number of decision points, loops,
logical operators and signature defaults in the whole sub statement, so that
the signature counts too. Forward declarations (no block) are skipped.

One more entry, named C<{file-level code}>, stands for the code outside the
named subs. Its CC is one plus the same counts for the file less those of the
named subs that are not inside another named sub, so it counts the C<BEGIN>,
C<CHECK>, C<INIT> and C<END> blocks, and any file-level anonymous sub, which at
run time has an entry of its own. Its line is that of the first top-level
statement that is neither a C<package> nor a sub.

Returns C<undef> if PPI is unavailable or the file fails to parse.

=back

=head1 PRIVATE SUBROUTINES

=over 4

=item _is_module_true($doc, $s)

Detects the trailing C<1> return value at the end of a module. Devel::Cover does
not count it as an executable statement.

=item _inside_for_parens($s)

Returns true if a statement is inside for-loop parentheses (e.g. the range
expression in C<for my $i (1..$n)>). Devel::Cover counts the for header as one
statement, not the inner expression separately.

=item _count_statements($doc, $includes, $compounds)

Counts executable statements: simple statements, compound headers, and an
estimated three markers per C<use>/C<require>.

=item _count_decisions($node)

Counts decision points within a PPI node (document or block): if/unless compound
statements, elsif clauses, ternary operators, and postfix if/unless modifiers.
Used by C<_count_branches> and C<_count_cc>.

=item _count_branches($doc)

Counts branch outcomes by delegating to C<_count_decisions> and doubling. Each
decision contributes two outcomes.

=item _logical_ops($doc)

Finds every logical operator token (C<&&>, C<||>, C<//>, C<and>, C<or>, C<xor>
and their assignment forms). Used by C<_count_conditions> and C<_count_mcdc>.

=item _count_conditions($doc)

Counts condition outcomes from logical operators.

=item _has_const_rhs($op)

Returns true if the right-hand side of a logical operator is a constant or
flow-control keyword, reducing the condition from 3 outcomes to 2.

=item _count_mcdc($doc)

Counts mcdc atomic conditions by grouping logical operators into their
enclosing statements, each group contributing its operator count plus one,
less one per const-RHS short-circuit operator.

=item _count_subroutines($doc, $includes)

Counts named subroutines and special blocks plus one BEGIN per
C<use>/C<require>.

=item _count_pod($doc)

Counts named subroutines, other than special blocks such as C<BEGIN>, as the
number of subs expected to have POD documentation.

=item _count_loops($node)

Counts loops within a PPI node: C<while>, C<until>, C<for> and C<foreach>
compound statements, the C<while> or C<until> of a C<do> block, and postfix
C<for>, C<foreach>, C<while> and C<until> modifiers. It skips a loop keyword
used as a hash key or a method name. A loop with no condition, such as
C<for (;;)> or C<while (1)>, compiles to no decision at run time but still
counts here.

=item _count_signature_defaults($node)

Counts the signature parameters within a PPI node that have a default given by
C<=>, C<//=> or C<||=>. A signature is a single C<PPI::Token::Prototype>
token, so it splits the text on commas and checks whether each part opens with
a scalar followed by one of those operators. A C<< => >> or C<==> inside a
default does not count, nor does an old-style prototype such as C<($$;@)>.

=item _count_cc($node)

Returns the decision points, loops, logical operators and signature defaults
within a PPI node, the CC of the node less one. Used by C<per_sub_complexity>.

=item _inside_named_sub($node)

Returns true if C<$node> is inside a named sub other than a C<BEGIN>,
C<CHECK>, C<INIT> or C<END> block.

=item _file_level_line($doc)

Returns the line of the first top-level statement that is neither a
C<package> nor a sub, or 1 if there is none.

=back

=head1 SEE ALSO

L<Devel::Cover>, L<Devel::Cover::DB>, L<PPI>

=head1 LICENCE

Copyright 2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
L<https://pjcj.net>

=cut

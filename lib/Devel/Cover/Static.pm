# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Static;

use v5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

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

sub _count_branches ($doc, $compounds) {
  my @decisions;
  for my $c (@$compounds) {
    my $type = $c->type // "";
    if ($type =~ /^(?:if|unless)$/) {
      push @decisions, $c;
      my $elsifs = $c->find(sub {
        $_[1]->isa("PPI::Token::Word") && $_[1]->content eq "elsif"
      }) || [];
      push @decisions, @$elsifs;
    }
  }

  # Ternary operators
  my $ternaries = $doc->find(sub {
    $_[1]->isa("PPI::Token::Operator") && $_[1]->content eq "?"
  }) || [];
  push @decisions, @$ternaries;

  # Statement modifiers: postfix if/unless
  my $modifiers = $doc->find(sub {
    return 0 unless $_[1]->isa("PPI::Token::Word");
    my $w = $_[1]->content;
    return 0 unless $w =~ /^(?:if|unless)$/;
    my $p = $_[1]->parent or return 0;
    !$p->isa("PPI::Statement::Compound")
  }) || [];
  push @decisions, @$modifiers;

  @decisions * 2
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

sub _count_conditions ($doc) {
  my $total = 0;

  my $ops = $doc->find(sub {
    $_[1]->isa("PPI::Token::Operator")
      && $_[1]->content =~ m!^(?:&&|\|\||//|&&=|\|\|=|//=|and|or|xor)$!
  }) || [];

  for my $op (@$ops) {
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

sub _count_subroutines ($doc, $includes) {
  my $subs = $doc->find(sub {
    $_[1]->isa("PPI::Statement::Sub") && $_[1]->name
  }) || [];

  @$subs + @$includes
}

sub _count_pod ($doc) {
  my $subs = $doc->find(sub {
    $_[1]->isa("PPI::Statement::Sub") && $_[1]->name
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
    branch     => _count_branches($doc, $compounds),
    condition  => _count_conditions($doc),
    subroutine => _count_subroutines($doc, $includes),
    pod        => _count_pod($doc),
  }
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
  # { statement => 12, branch => 4, condition => 2, subroutine => 3, pod => 3 }

=head1 DESCRIPTION

This module provides static analysis of Perl source files using PPI. It
estimates the number of coverable constructs (statements, branches, conditions,
subroutines, and pod) without executing the code.

It is used by L<Devel::Cover::DB> to populate coverage data for files discovered
via C<--select_dir> that were never exercised by any test. The counts allow
reports to show meaningful 0/N ratios rather than bare zeroes.

Returns C<undef> if PPI is not installed or the file cannot be parsed.

=head1 SUBROUTINES

=over 4

=item count_criteria($file)

The sole public entry point. Parses C<$file> with PPI and returns a hashref of
estimated coverable counts:

  {
    statement  => $n,
    branch     => $n,
    condition  => $n,
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

B<Subroutines> count named subs plus one BEGIN per C<use>/C<require>.

B<Pod> counts named subroutines (the number of subs that should have
documentation).

=back

=head1 PRIVATE SUBROUTINES

=over 4

=item _is_module_true($doc, $s)

Detects the trailing C<1> return value at end of a module. These are not counted
as executable statements by Devel::Cover.

=item _inside_for_parens($s)

Returns true if a statement sits inside for-loop parentheses (e.g. the range
expression in C<for my $i (1..$n)>). Devel::Cover counts the for header as one
statement, not the inner expression separately.

=item _count_statements($doc, $includes, $compounds)

Counts executable statements: simple statements, compound headers, and an
estimated three markers per C<use>/C<require>.

=item _count_branches($doc, $compounds)

Counts branch outcomes from if/unless blocks, elsif clauses, ternary operators,
and postfix if/unless modifiers. Each decision contributes two outcomes.

=item _count_conditions($doc)

Counts condition outcomes from logical operators (C<&&>, C<||>, C<//>, C<and>,
C<or>, C<xor> and their assignment forms).

=item _has_const_rhs($op)

Returns true if the right-hand side of a logical operator is a constant or
flow-control keyword, reducing the condition from 3 outcomes to 2.

=item _count_subroutines($doc, $includes)

Counts named subroutines plus one BEGIN per C<use>/C<require>.

=item _count_pod($doc)

Counts named subroutines as the number of subs expected to have POD
documentation.

=back

=head1 SEE ALSO

L<Devel::Cover>, L<Devel::Cover::DB>, L<PPI>

=cut

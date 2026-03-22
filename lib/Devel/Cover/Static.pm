# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Static;

use v5.20.0;
use strict;
use warnings;
use feature qw( signatures );
no warnings qw( experimental::signatures );

my $Have_ppi;

BEGIN { $Have_ppi = eval { require PPI; 1 } }

# Keywords/ops that DC treats as constant or flow-control RHS, reducing a
# condition from 3 outcomes to 2. Mirrors $Const_right and the OP_* checks in
# Cover.xs.
my %Const_rhs = map { $_ => 1 }
  qw( die warn croak confess next last redo goto return exit exec undef bless );

# Detect the trailing "1" return value at end of module - DC does
# not count this as an executable statement.
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

# Skip statements inside for-loop parentheses, e.g. the range
# expression "1..$n" in "for my $i (1..$n)". DC counts the for
# header as one statement, not the range separately.
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

  # Each compound header (if/for/while/unless) is an executable stmt
  my $compound_headers = @$compounds;

  # DC records ~3 statement markers per use/require (BEGIN execution)
  my $include_stmts = @$includes * 3;

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
    # Note: for/while/until with conditions produce DC branches, but
    # distinguishing conditional loops from range-for is unreliable in PPI. Omit
    # loops for now - slight undercount is preferable to overcounting.
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

  # DC tracks branch outcomes (true + false per decision)
  @decisions * 2
}

# Check whether the RHS of a logical operator is a constant or flow-control
# keyword. In PPI, the RHS is the next significant sibling after the operator
# token.
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

  # Find && || // and or xor operators (all PPI::Token::Operator)
  my $ops = $doc->find(sub {
    $_[1]->isa("PPI::Token::Operator")
      && $_[1]->content =~ m{^(?:&&|\|\||//|&&=|\|\|=|//=|and|or|xor)$}
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

  # DC counts one BEGIN sub per use/require
  @$subs + @$includes
}

# Pod coverage total = number of named user subs (DC checks whether
# each sub has corresponding documentation).
sub _count_pod ($doc) {
  my $subs = $doc->find(sub {
    $_[1]->isa("PPI::Statement::Sub") && $_[1]->name
  }) || [];
  0 + @$subs
}

# Count coverable criteria in a source file using static analysis.
# Returns undef when PPI is unavailable or the file cannot be parsed.
# Returns { statement => N, branch => N, condition => N,
#   subroutine => N, pod => N }.
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

1

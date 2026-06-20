# Coverage for `package` Declarations

Perl provides two forms of `package` declaration. This document describes how
Devel::Cover handles each, and the phantom statement artefact that both the
block form and `class` blocks produce.

## The Two Forms

A bare `package` statement switches the current package for the remainder of the
enclosing scope:

```perl
package Foo;
sub bar { 1 }
```

A block-form `package` declaration scopes the package change lexically:

```perl
package Foo {
  sub bar { 1 }
}
```

Both are compile-time constructs. Neither form generates a runtime-executable
statement of its own - the package name is registered at compile time, and
coverage tracking applies only to the subroutines and statements inside.

## Block-Form Optree

`package Foo { }` (and `class Foo { }` from the `class` feature - see
`class.md`) compile the body block as an `enterloop/leaveloop` pair in the
enclosing CV. The loop body is a `lineseq` with a `stub` op followed by an
optimiser-generated trailing `nextstate` at the closing `}`:

```text
leave
  enter
  nextstate               <- line of "package Foo {"
  leaveloop
    enterloop
    lineseq
      stub
      null (ex-nextstate) <- line of "}", optimised away
  ...
```

The `ex-nextstate` is a `B::COP` with `name="null"` and `type=0` - the optimiser
has nullified it because it is unreachable. Its `op_next` pointer still points
to the `leaveloop` (from the original execution chain before optimisation), but
`stub`'s own `op_next` bypasses it, going directly to `leaveloop`. The null op
is therefore never visited at runtime.

## The Phantom Statement

The XS op walker (`dc_walk_ops_r` in `Cover.xs`) visits the optree
structurally, so it reaches optimised-away `ex-nextstate` ops as children of
their `lineseq`. An `ex-nextstate` is an `OP_NULL` whose `op_targ` records the
original `OP_NEXTSTATE`/`OP_DBSTATE`. The most common one sits on the line of a
closing `}` whose `nextstate` the optimiser nullified.

If such an op were registered as a statement, `add_statement_cover` would record
a statement at the `}` line that the runtime `dc_nextstate` hook can never
count, producing a false `*0` (uncovered statement) on the closing brace.

The walker filters these in two places. First, the XS layer only emits a
`null_statement` for an `ex-nextstate` that still has a sibling. A dead
end-of-block `ex-nextstate` is the last child of its `lineseq`, so it has none
and is skipped outright:

```c
case OP_NULL:
  if (op->op_targ == OP_NEXTSTATE || op->op_targ == OP_DBSTATE) {
    if (OpSIBLING(op))
      dc_walk_callback(aTHX_ op, callback, "null_statement", cv);
  }
  break;
```

Second, `_walk_statement` applies a three-hop `->next` guard (`$nnnext`) so any
statement op with no real successors is skipped before `add_statement_cover`
runs:

```perl
my $nnnext = "";
eval {
  my $next  = $op->next;
  my $nnext = $next && $next->next;
  $nnnext = $nnext && $nnext->next;
};
return unless $nnnext;
```

## Bare `package` Inside a Block

A bare `package Pkg;` statement followed immediately by another statement (such
as `use overload` or a `sub` declaration) has its `nextstate` nullified by the
optimiser, the same `ex-nextstate` pattern as above. The structural walk and the
`$nnnext` guard keep a false `*0` from appearing on the `package Pkg;` line.

## What Is Tracked

Subroutines declared inside either form of `package` block are discovered and
tracked through the normal `walksymtable` path. Coverage for their bodies (stmt,
bran, cond, sub) is unaffected by the package declaration itself.

The `package` declaration line and its closing `}` are not coverable statements
and do not appear in coverage output.

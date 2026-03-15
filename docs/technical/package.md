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

Devel::Cover's `deparse` hook processes every op that `B::Deparse` visits,
including the unreachable `ex-nextstate`. The hook identifies `B::COP` ops and
uses a three-hop `->next` chain (`$nnnext`) as a heuristic to detect whether the
op is part of real executable code. Because the `ex-nextstate`'s `op_next` still
points to `leaveloop` (a real op), `$nnnext` is truthy and the heuristic passes
even though the op itself is never executed.

Without a guard, `add_statement_cover` would be called for this op, registering
a statement at the `}` line that the runtime `dc_nextstate` hook can never
count. The result is a false `*0` (uncovered statement) on the closing brace.

The guard in the `deparse` hook excludes `B::COP` ops whose name is `"null"`:

```perl
if ($nnnext && $name ne "null") {
  add_statement_cover($op) unless $Seen{statement}{$$op}++;
}
```

A `B::COP` with `name="null"` is always an optimised-away `ex-nextstate`. Its
runtime `op_next` may be valid, but the op itself is never dispatched, so it
must not be registered as a coverable statement.

## Bare `package` Inside a Block

A bare `package Pkg;` statement generates a `nextstate` in the enclosing scope.
When it is immediately followed by another statement (such as `use overload` or
a `sub` declaration), the optimiser nullifies the `package` nextstate - the same
`ex-nextstate` pattern as above. The same `name ne "null"` guard prevents a
false `*0` from appearing on the `package Pkg;` line.

## What Is Tracked

Subroutines declared inside either form of `package` block are discovered and
tracked through the normal `walksymtable` path. Coverage for their bodies (stmt,
bran, cond, sub) is unaffected by the package declaration itself.

The `package` declaration line and its closing `}` are not coverable statements
and do not appear in coverage output.

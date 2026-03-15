# Coverage for Perl's `class` Feature

Perl 5.38 introduced a native object system via `use feature 'class'`. This
document describes how Devel::Cover collects coverage for the constructs it
introduces and what limitations remain.

## Background

The `class` feature (formerly known as Corinna) adds four new keywords:

- `class` - declares a class (analogous to `package`, but with extra semantics
  and an auto-generated `new` constructor)
- `field` - declares a per-instance lexical variable
- `method` - declares a named method on the class
- `ADJUST` - a block that runs once per object during construction

Classes inherit from one parent via the `:isa` class attribute. Fields carry
optional attributes: `:param` to accept constructor arguments, `:reader` to
auto-generate a reader accessor, and `:writer` to auto-generate a writer.

## CV Discovery for Methods

Every CV (Perl's internal representation of a subroutine) compiled from a
`method` declaration begins with a `methstart` op. The `methstart` op is a
`B::UNOP_AUX` whose purpose is to initialise `$self` and make per-instance field
storage available inside the method body. Only after it executes does the normal
`nextstate` op appear, which carries the source file and line number.

Devel::Cover's CV discovery path is:

1. `walksymtable` visits every GV in every package stash.
2. `B::GV::find_cv` extracts the CV from each GV and calls `check_file`.
3. `check_file` calls `$cv->START` and, if the result is a `B::UNOP_AUX` named
   `methstart`, advances one hop (`$op->next`) to reach the `nextstate` that
   carries file information. A `ref` check guards the `->name` call so that
   `B::NULL` ops are handled safely.

`sub_info` similarly skips a leading `methstart` via `$start->sibling` to locate
the true start of the method body. For methods without a signature this yields
`nextstate` directly; for methods with a signature it yields the
`null`/`ex-argcheck` node that the existing signature-handling code processes.

## The `methstart` Optree

For a method with no signature:

```text
leavesub
  lineseq
    methstart       <- $cv->START; initialises $self and field storage
    nextstate       <- first B::COP; carries file and line number
    ... body ...
```

For a method with a signature:

```text
leavesub
  lineseq
    methstart
    null            <- ex-argcheck; wraps signature processing
      lineseq
        nextstate   <- inside signature prologue
        argcheck
        argelem(s)
    nextstate       <- after signature, before body
    ... body ...
```

After skipping `methstart` with `->sibling`, the existing signature path in
`sub_info` handles the `null` node without further changes.

## What Is Tracked

| Construct                           | Coverage                    |
| ----------------------------------- | --------------------------- |
| Named `method`                      | stmt, bran, cond, sub       |
| `method` with signature             | stmt, bran, cond, sub       |
| `my method` (lexical/private)       | stmt, bran, sub             |
| Anonymous `method` (returned value) | stmt, bran, sub             |
| Overriding `method` in subclass     | stmt, bran, cond, sub       |
| `ADJUST` block                      | stmt, sub (see `adjust.md`) |

## What Is Not Tracked

### Auto-generated accessors (`:reader` and `:writer`)

Fields declared with `:reader` or `:writer` have accessor methods generated
entirely by the Perl compiler. These CVs contain no `nextstate` op - the optree
goes directly from `methstart` to `argcheck` to the field access or assignment.
There is no user-written source line to attach coverage to, so they are excluded
from tracking.

### Field initialiser expressions

Field defaults (`field $x = expr`) execute during object construction inside the
compiler-generated constructor CV. They are not standalone CVs and do not
produce independent coverage entries.

## Test Cases

Three test files cover the class feature, one per Perl release that added
new constructs:

- `tests/class38` (5.38+): `class`, `field :param`, `method`, `ADJUST`,
  `:isa`, anonymous methods, methods with signatures, branch coverage.
- `tests/class40` (5.40+): extends class38 with `:reader` field attributes
  and their auto-generated accessors.
- `tests/class42` (5.42+): extends class40 with `:writer` field attributes,
  `my method` (lexical/private methods), and `method call_private`.

The golden output files in `test_output/cover/` serve as regression tests
for all three.

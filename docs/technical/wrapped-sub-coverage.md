# Coverage for Subs Swapped Out of the Symbol Table

A named sub can be replaced in the symbol table by a wrapper while the original
sub is kept alive somewhere the wrapper can reach. The classic case is a method
modifier - Moose's `around`, and the same pattern in Moo,
`Class::Method::Modifiers`, `Hook::LexWrap` and hand-rolled code such as

```perl
sub original { ... }
my $orig = \&original;
*original = sub { ... $orig->(@_) ... };
```

After the swap `*original{CODE}` is the wrapper. The original sub still exists
and still runs (the wrapper calls it), but it is no longer reachable from any
glob in the symbol table. It survives only as a reference the wrapper closes
over.

## Why the coverage was lost

Devel::Cover builds its subroutine and statement structure at report time by
walking for CVs from two roots (`check_files` in `Devel/Cover.pm`): the symbol
table (every package's glob `CODE` slots, via `walksymtable`) and the pads of
the CVs it finds (`pad_cvs`, which picks up anon prototypes and lexical `my`
subs).

A displaced original is in neither place. Its glob now holds the wrapper, and it
is not an anon prototype in a pad. So although its ops were instrumented at
compile time and its counts were recorded at run time, no structure entry is
built for it and the counts are dropped. The file then reports full coverage
with the original's body invisible - the same silently-inflated percentage
described in `require-toplevel-coverage.md`.

This is issue GH-308 (its title notes it "affects method modifiers and
friends").

## What is recovered

`pad_cvs` follows a pad slot that holds a reference, not only a slot that holds
a CV directly (`ref_cvs`):

- a reference straight to a CV (the `my $orig = \&original` form), and
- a reference one level deep into a plain array or hash the sub closes over.

The second case is how Class::MOP, and so Moose, keeps the original. The wrapper
closes over a plain hash whose `orig` entry is the original method. `orig` sits
one container deep whatever the number or mix of modifiers, because Class::MOP
coalesces `before`, `after` and `around` into a single wrapper.

Two rules keep this precise and cheap. A CV reached through a reference is kept
only if it is a genuinely named sub (`recoverable_sub`) - not an anon, and not
an internal clone with a generated name such as Moose's `:around` modifier CV or
a pragma's `BEGIN` block. Those share a body with a sub already found the normal
way, so recording them again would duplicate it, and because the duplicate
shares a start op with the original the report-time dedup would pick between
them non-deterministically. Descent also stops after one container and does not
enter blessed containers, so a sub closing over an object does not drag the
object's whole graph into the walk. Magical containers are not entered either. A
tied container's contents come from its `FETCH`, and the report-time walk must
never run user code - and `B::AV::ARRAY` on a tied array reads the empty real
array with the size the tie magic reports, which crashes the process.

The cost is paid only when building the report, and only for subs that close
over references. A program with no method modifiers pays effectively nothing. A
program full of them pays in proportion to the number recovered, which is the
inherent cost of covering subs that were previously absent.

The tests are in `t/internal/wrapped_sub.t`: the direct reference form, the
hash-held and array-held forms, a wrapper closing over a reference to a tied
array, and a real Moose `around` modifier (skipped when Moose is not installed).

## Known limitations

Recovery is a heuristic, not a guarantee. It finds the original only where the
wrapper reaches it through a pad, within one plain container. It does not find
an original that is

- nested two or more containers deep,
- held inside a blessed object the wrapper closes over, or
- kept in a package variable and looked up at call time rather than closed over
  (such an original is in no pad at all).

## A route to a real guarantee

The heuristic re-discovers subs by walking the symbol table and pads, so it is
bound by where a sub can be reached from. A mechanism that instead remembers
each sub as it runs would not have that bound.

Devel::Cover already intercepts every call through `dc_entersub` (it replaces
`PL_ppaddr[OP_ENTERSUB]`). That hook could record the entered CV, so every sub
that actually executes is remembered regardless of what later happens to its
glob. A displaced original still runs - the wrapper calls it - so it would be
recorded even in the cases the heuristic misses above (each of those originals
does execute and is simply unreachable from the walk roots at report time). A
sub that never runs needs no run coverage and is still reported as uncovered
from the symbol-table walk, so entry capture is enough to close the gap for
executed subs. At report time the recorded CVs are merged into the walk's
results before the structure is built, and the existing subroutine, statement
and branch machinery covers them.

The reference held to each recorded CV must be weak. A weak reference does not
raise the CV's reference count, so DESTROY timing, memory use and what stays
alive are all unchanged - the tool must not alter the behaviour of the program
it measures. It also degrades sensibly. When a CV is freed before the report is
built (a closure created, called and dropped mid-run), `Scalar::Util::weaken`
nulls the reference to `undef`, so the report step skips it rather than reading
a freed or reused slot. Those subs ran but their optree is gone, so no structure
can be built for them, and they are counted as dropped rather than crashing the
report. A weak reference is safe against address reuse in a way raw address
tracking is not.

The costs are why this is a larger change than the heuristic and belongs on its
own branch. `dc_entersub` is on the call hot path, so recording a CV there - a
lookup to skip ones already seen, and a weaken on first sight - is collection
cost, the more sensitive kind, and would likely be gated behind an option. It
holds one small weak-reference SV per distinct executed CV for the length of the
run, and the interaction with threaded builds (weak references are
per-interpreter) and with getting the entered CV cleanly for XS subs both need
care. Measuring the hot-path cost is the first step before committing to it.

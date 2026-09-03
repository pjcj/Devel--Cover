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

## Limits of the heuristic

The pad walk finds the original only where the wrapper reaches it through a pad,
within one plain container. It does not find an original that is

- nested two or more containers deep,
- held inside a blessed object the wrapper closes over, or
- kept in a package variable and looked up at call time rather than closed over
  (such an original is in no pad at all).

Entry recording, below, covers all three (GH-606).

## Entry recording

The heuristic re-discovers subs by walking the symbol table and pads, so it is
bound by where a sub can be reached from. Entry recording removes that bound by
remembering each sub as it runs.

Devel::Cover intercepts every call through `dc_entersub` (it replaces
`PL_ppaddr[OP_ENTERSUB]`; the `runops_cover` loop mirrors it under
`-replace_ops 0`). `record_entered_sub` there records the CV about to be
entered, so every sub that actually executes is remembered regardless of what
later happens to its glob. A displaced original still runs - the wrapper calls
it - so it is recorded even where the pad walk cannot reach it. A sub that never
runs needs no run coverage and is still reported as uncovered from the
symbol-table walk, so entry capture closes the gap for executed subs. At report
time `get_entered_subs` hands the recorded CVs to `_seed_entered_subs`, which
merges them into `%Cvs` - filtered through `recoverable_sub` and `check_file`
like the pad-walk recoveries - before `check_files` snapshots `@Cvs`, and the
existing subroutine, statement and branch machinery covers them.

Only named subs are recorded: XS subs, anonymous subs, closure clones and the
compile-phase blocks (`BEGIN` and friends) are skipped. Anonymous subs and
clones are covered through the pad walk when they survive, a clone shares its
start op with its prototype so recording it would add a duplicate, and the phase
blocks' early release must not be delayed.

The same hook counts entries. `count_sub_entry` increments a count keyed by the
sub's root op, which a closure clone shares with its prototype, whenever
subroutine or pod coverage is on. Subroutine coverage is otherwise derived from
the execution count of a sub's first statement. Without statement coverage,
every sub used to be reported as uncovered. `add_subroutine_cover` reads the
entry count when statement coverage is off. With statement coverage on, it keeps
the statement-derived count, so such runs report exactly what they did before.
The entry count misses calls that bypass `entersub`: `goto &sub`, `sort subname`
and, under `-replace_ops 0`, subs called from C such as `DESTROY` and overload
methods.

The reference held to each recorded CV is strong, not weak. A weak reference
would be nulled the moment a sub is freed, which is exactly the case that needs
covering: a sub redefined at runtime (`*foo = sub { ... }`) frees the original
CV on the spot, since the glob held the only reference. With a strong reference
the original's optree survives to report time, so its structure can be built and
its counts - keyed by op address - can never be confused with a later op reusing
the same address. This closes the "Redefined subroutines" limitation documented
in the user docs since GH-88, for any original that ran at least once. An
original redefined before it ever runs is still lost: it was never entered, and
its optree is freed before any coverage could attach.

Recording named subs only keeps the observable cost contained. A named CV lives
to the end of the run anyway except when redefined or its package is deleted, so
holding it does not change what stays alive, and closure DESTROY timing - the
sensitive case, see GH-118 - is untouched because closures are never recorded. A
redefined sub's pad now survives to report time instead of being freed at
redefinition, which is the price of reporting on it.

The hot-path cost is a few flag tests per call plus one hash lookup, keyed on
the CV pointer, for named subs already recorded. Measured on a worst-case
microbenchmark (ten million calls of a one-line named sub under statement
coverage, nothing else) the difference from the previous code was about two
percent, within run-to-run noise, so recording is always on rather than behind
an option.

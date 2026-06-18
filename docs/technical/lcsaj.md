# Linear Code Sequence and Jump (LCSAJ) Coverage

This document describes Linear Code Sequence and Jump (LCSAJ) coverage and what
would be required to add it to Devel::Cover.

LCSAJ is **not implemented** and not planned. The `path` placeholder reserved
for it is being removed alongside the MC/DC work (GH-478). This document records
why LCSAJ was investigated and ruled out in favour of MC/DC.

## Overview

A LCSAJ is a triple `(start, end, target)` where:

- `start` is the first statement of a linear sequence (a basic-block leader: the
  start of a program/sub, or any statement that is a target of a jump).
- `end` is the last sequential statement before a jump (any control-flow op).
- `target` is the destination the jump goes to.

100% LCSAJ coverage requires that every triple be exercised. The metric was
defined by Woodward, Hennell, and Hedley (1980) as a path-coverage approximation
that was tractable to compute for large programs of the era.

LCSAJ subsumes branch coverage (every branch's two outcomes correspond to two
distinct triples) and statement coverage (every statement appears in some
triple), but it is weaker than full path coverage (which would require
enumerating every distinct end-to-end path through the control-flow graph, an
exponentially-sized set).

## Why LCSAJ is stronger than branch coverage

Branch coverage requires each conditional to go both ways but does not require
those branches to be exercised in *combination*. The classic example from
`lib/Devel/Cover/Tutorial.pod`:

```perl
$h = undef;
if ($x) {
    $h = { a => 1 };
}
if ($y) {
    print $h->{a};
}
```

100% branch coverage is achieved with `($x, $y)` set to `(1, 1)` and `(0, 0)`.
Both `if`s go true and false. But `(0, 1)` triggers a runtime error: `$h` is
still undef when its dereference is attempted. LCSAJ forces the second `if` to
be reached after both true and false outcomes of the first, so the bug is
exposed.

## Status: the placeholder

The criterion list reserved the name `path` for LCSAJ across these locations:

- `Cover.xs` defined `Path 0x10` and exposed `coverage_path()`.
- `lib/Devel/Cover/DB.pm` included `path` in `@Criteria` and `@Criteria_short`.
- `lib/Devel/Cover.pm` had `delete $Coverage{path};  # not done yet` to filter
  it out before collection.
- `t/internal/criteria.t` exercised the `path` flag in
  `set_coverage`/`get_coverage`.
- `lib/Devel/Cover/Collection.pm` filtered `path` out of cpancover reports.

The placeholder dated back to the project's early development. `docs/TODO`
listed "Collect data for path coverage" among long-standing planned
enhancements. `Tutorial.pod` section 2.3 describes path coverage as a general
metric and notes it is "also known as predicate, basis path and LCSAJ"; that
description is left in place as educational content alongside sections on the
other criteria.

GH-478 renames the `path` slot in-place to `mcdc`, reusing the bit (Path 0x10
becomes Mcdc 0x10) and the `@Criteria` position. The obsolete `docs/TODO` line
is dropped.

## Mapping LCSAJ onto Perl

In a sequential language LCSAJs are derived from line-level control flow. In
Perl the natural unit is the op rather than the line, so the practical
implementation must work at the op level and aggregate to lines for display.

### Basic-block leaders

The first op of any CV is a leader. After that, every successor of a multi-
target op is a leader, as is every target of any jump. In Perl this includes:

- The first op after any logop (`OP_AND`, `OP_OR`, `OP_DOR`, `OP_XOR`)
- The two arms of `OP_COND_EXPR` (if/else, ternary)
- The top-of-loop op for any `OP_LEAVELOOP`
- The continuation of `OP_NEXT`/`OP_LAST`/`OP_REDO`
- Any label that is the target of `OP_GOTO`
- The continuation after `OP_LEAVEEVAL`
- The first op of each entered eval block

### Jumps

Any op that may transfer control non-sequentially is a jump end:

- The logops listed above
- `OP_COND_EXPR`
- Loop control: `OP_NEXT`, `OP_LAST`, `OP_REDO`, `OP_LEAVELOOP`
- Sub exit: `OP_RETURN`
- Process exit: `OP_DIE`, `OP_EXIT`, `OP_EXEC`
- `OP_GOTO` (label, sub, code-ref)
- `OP_ENTERSUB` only if it is a `goto &name` tail call; ordinary calls are
  conventionally treated as a single node with one successor.

### Perl-specific complications

- `goto LABEL` with a runtime-computed string is not statically resolvable. The
  CFG must accept that some triples cannot be enumerated.
- `goto &name` is a tail call: it looks like `entersub` but exits the CV.
- `die` from anywhere can transfer to any enclosing eval; the CFG must add
  eval-target edges that are reachable from arbitrary ops.
- Sort/grep/map blocks have detached optrees with their own start/end semantics.
- Format `~` lines, regex `(?{...})` blocks, and tied-variable callbacks have
  their own optree fragments.
- The optree for boolean expressions is rewritten across Perl versions (e.g. the
  5.43.8 changes around `OPpSTATEMENT`). Any CFG built by Devel::Cover must keep
  up.

## What would need to be added

### CFG construction

The hardest part. For each CV, derive a successor map from the optree. The
decision table:

| Op type                        | Successor logic                             |
| ------------------------------ | ------------------------------------------- |
| Most ops                       | `op_next`                                   |
| `OP_AND`/`OP_OR`/`OP_DOR`      | `op_next` (short-circuit) and right child   |
| `OP_XOR`                       | `op_next` (no short-circuit)                |
| `OP_COND_EXPR`                 | `op_other` (false) and right child (true)   |
| `OP_NEXT`/`OP_LAST`/`OP_REDO`  | enclosing `OP_LEAVELOOP` continuation       |
| `OP_LEAVELOOP`                 | back-edge to top, plus exit                 |
| `OP_GOTO`                      | label resolution (often runtime only)       |
| `OP_RETURN`/`OP_DIE`/`OP_EXIT` | leaves the CV                               |
| `OP_ENTERSUB`                  | one node, one successor (call as black box) |
| `OP_ENTEREVAL`/`OP_LEAVEEVAL`  | normal flow plus die-target                 |
| Sort/grep/map blocks           | detached optree, separate sub-CFG           |

Estimated 600-1000 lines of new Perl/XS plus Perl-version conditional code that
requires ongoing maintenance.

### Leader and triple enumeration

Once the successor map is built, leaders are op[0] of the CV plus every op with
in-degree > 1, plus every successor of a multi-target op. Walk forward from each
leader along single-successor edges until a branch op is reached, then emit
`(leader, branch_op, target)` for each target. Estimated 150-300 lines.

### Runtime collection

Two designs are plausible:

- **Track current leader.** Maintain a `current_leader` register per CV call
  frame. On entering any leader, update it. At every branch op, observe the
  outcome (already done for branch coverage) and record the triple
  `(current_leader, this_op, chosen_target)`.

- **Edge-only collection plus offline reconstruction.** Collect every CFG edge
  taken at runtime. At report time, walk the static CFG and determine which
  `(leader → end → target)` chains are reachable from the observed edges.

The first is closer to the existing branch model. Estimated 300-500 lines of XS
plus the storage layer.

### Criterion class, reports, tests

A new `lib/Devel/Cover/Lcsaj.pm` modelled on `Branch.pm`. Reporter support
analogous to the existing `Branches` and `Conditions` sections. Test files
exercising different control-flow patterns. Golden file regeneration for the new
summary column across all tracked Perl versions.

## Cost / value summary

- New code: 3000-5000 lines.
- Calendar: 4-8 weeks for someone deep in the codebase.
- Maintenance: per-Perl-version updates as the optree changes.

LCSAJ has fallen out of fashion. Modern safety-critical work prefers MC/DC
(DO-178C, ISO 26262), which is the lighter and more precisely useful metric.
LCSAJ in Perl is also expensive to implement honestly because Perl's control
flow is much richer than the procedural FORTRAN the original definition assumed.

The `path` placeholder is removed as part of GH-478, with the reserved
`Path 0x10` flag bit repurposed for MC/DC. The tutorial's path-coverage section
is left in place as a general description of the metric. See
`docs/technical/mcdc.md` for the metric being added.

## References

- Woodward, M.R., Hennell, M.A., and Hedley, D. (1980). "Experience with path
  analysis and testing of programs." *IEEE Transactions on Software Engineering*
  SE-6(3), 278-286.
- `lib/Devel/Cover/Tutorial.pod` section 2.3 for the general description of
  path/LCSAJ coverage as a metric.
- `docs/technical/branches_and_conditions.md` for related coverage data
  collection.
- `docs/technical/mcdc.md` for the alternative stronger metric.

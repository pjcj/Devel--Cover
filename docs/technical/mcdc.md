# Modified Condition/Decision Coverage (MC/DC)

This document describes Modified Condition/Decision Coverage (MC/DC), how it
relates to Devel::Cover's existing condition coverage, and how it is implemented
as a separate criterion.

## Overview

MC/DC requires that for each atomic condition `C` in a decision, the test suite
contains a pair of executions where:

- `C`'s truth value differs between the two
- All other atomic conditions are compatible (held constant or masked)
- The decision's overall outcome differs as a result

The metric proves that each input "independently affects" the decision's output.
It was introduced by Chilenski and Miller in 1994 to give the strongest
practical structural coverage available without requiring the exponential effort
of full multiple-condition coverage.

MC/DC is mandated by:

- **DO-178B/C** Level A (avionics) - mandatory at the highest assurance level
- **ISO 26262** ASIL C/D (automotive) - recommended
- **IEC 61508** SIL 3/4 (industrial functional safety) - recommended

## Variants

Three variants are accepted in industry practice:

- **Unique-cause MC/DC** is the original 1994 definition. Only one atomic
  condition may differ between the demonstrating pair. It is strict and hard to
  satisfy when conditions are coupled (the same expression appears more than
  once in the decision).

- **Masking MC/DC** permits other conditions to differ between the pair if their
  values are masked (do not affect the outcome). It has been accepted by DO-178C
  since 2011 and is the natural fit for short-circuit languages, because the
  unevaluated operand of `&&`/`||` is masked by definition.

- **Unique-cause + masking** is a hybrid. It is relevant only when conditions
  repeat in the decision.

For Perl, **hybrid MC/DC** is the appropriate choice. It tries unique-cause
first (the strict 1994 definition) and falls back to masking only when
unique-cause is impossible because of coupling - the same atomic condition
appearing more than once in a decision. In Perl, coupling is rare; expressions
like `$a && (!$a || $b)` are tautologies that almost never survive review. So
for typical Perl code hybrid behaves like unique-cause, while remaining
well-defined for the unusual cases.

In the current implementation coupling does not reach the analyser at all.
Decisions are recorded per logop (see Limitations), so repeated atomic
conditions end up in separate truth tables and the masking fallback is never
triggered by real code. It remains as defensive code rather than an active path.

Pure masking is over-permissive in a short-circuit language: any execution where
the left operand short-circuits masks every condition on the right, so under
loose masking rules a `(F,F,F)` test against `(A && B) || C` could be paired
with `(T,T,F)` to "demonstrate" `A`'s independence even though `A`'s value
didn't actually drive the outcome flip on its own. Hybrid closes that loophole
by preferring unique-cause where possible.

## A worked example

The decision `(A && B) || C` is a small canonical MC/DC example: easy to trace
by hand, but structurally rich enough that condition coverage and MC/DC diverge.
The example below uses that decision dressed up as an article-editing
controller; the dressing is illustrative for this document, while the underlying
logical pattern is the kind used in the standard tutorials (Hayhurst et al.
2001).

### The intended specification

A user may edit an article when they own it *and* the article is unlocked, *or*
they have admin rights:

```perl
sub may_edit ($is_owner, $unlocked, $is_admin) {
    return ($is_owner && $unlocked) || $is_admin;
}
```

### The bug

The bug is a single misplaced `!`:

```perl
sub may_edit_buggy ($is_owner, $unlocked, $is_admin) {
    return ($is_owner && !$unlocked) || $is_admin;
}
```

This swaps the meaning of `$unlocked`: owners can edit only when the article is
*locked*. Two real failure modes follow - normal editing breaks for owners on
unlocked articles, and a privilege-escalation path opens for owners on locked
articles.

### Tests achieving 100% statement, branch, and condition coverage

| #   | `$is_owner` | `$unlocked` | `$is_admin` | Correct | Buggy |
| --- | ----------- | ----------- | ----------- | ------- | ----- |
| 1   | T           | T           | T           | T       | T     |
| 2   | T           | F           | T           | T       | T     |
| 3   | F           | F           | T           | T       | T     |
| 4   | F           | F           | F           | F       | F     |

These four tests achieve:

- 100% statement coverage.
- 100% branch coverage (the outer decision goes both ways: tests 1-3 → T; test 4
  → F).
- 100% condition coverage. Between them the four tests cover every row of the
  outer `||`'s `or_3` table (`l`, `!l && r`, `!l && !r`) and every row of the
  inner `&&`'s `and_3` table (`l && r`, `l && !r`, `!l`).

The buggy implementation produces the same results as the correct one on all
four tests. The bug is invisible to statement, branch, and condition coverage.

The test set is not contrived. The author had a free choice between `(T,T,T)`
and `(T,T,F)` for the position covering "outer-l + inner-l && r", and between
several `(F,F,?)` variants for the inner-`!l` row. The picks shown are perfectly
natural; nothing in the condition-coverage metric pushed the author towards a
different combination.

### What MC/DC additionally requires

Hybrid MC/DC requires, for each atomic condition, a pair of executions where
flipping that condition flips the outcome with the others held compatibly.
Perl's short-circuit operators leave the unevaluated side unobserved, so each
test's observed input vector carries `X` in any column the operator skipped.
Short-circuit-aware unique-cause treats `X` as compatible with any concrete
value in the same column (see "Short-circuit and masking" below).

The four tests above produce these observed input vectors:

| Test | `$is_owner` | `$unlocked` | `$is_admin` | Result |
| ---- | ----------- | ----------- | ----------- | ------ |
| 1    | T           | T           | X           | T      |
| 2    | T           | F           | T           | T      |
| 3    | F           | X           | T           | T      |
| 4    | F           | X           | F           | F      |

Per atomic condition:

- `$is_owner`'s pair: Test 1 `(T,T,X)` and Test 4 `(F,X,F)`. Target flips T↔F;
  `$unlocked` is `T` vs `X`, `$is_admin` is `X` vs `F`; both are
  short-circuit-compatible. Outcome flips T↔F. Pair found.
- `$is_admin`'s pair: Test 3 `(F,X,T)` and Test 4 `(F,X,F)`. Target flips,
  `$is_owner` matches, `$unlocked` is `X` in both. Outcome flips. Pair found.
- `$unlocked`'s pair: needs two rows where `$unlocked` is concrete (not `X`),
  with `$is_owner` matching and the outcome flipping. Test 1 `(T,T,X)` covers
  the T side. The F side requires `$is_owner = T`, `$unlocked = F`, and a result
  of F (so `$is_admin = F` too). The input `(T,F,F)` is not in the four-test
  set. MC/DC forces it:

| #   | `$is_owner` | `$unlocked` | `$is_admin` | Correct | Buggy           |
| --- | ----------- | ----------- | ----------- | ------- | --------------- |
| 5   | T           | F           | F           | F       | T ← bug exposed |

Test 5 is "the user owns a locked article, no admin override" - the correct
implementation denies the edit; the buggy implementation grants it because
`!$unlocked` is true. The assertion fails and the bug is caught.

### Why this matters

Condition coverage tells you "every leaf operator was exercised both ways."
MC/DC tells you "the test set proves each input genuinely affects the output."

The metric difference isn't that condition coverage missed a row; it didn't. The
difference is that condition coverage gave the test author freedom in picking
*which* tests covered each row, and that freedom let the chosen tests miss the
bug. Hybrid MC/DC removes the freedom by tying each test's purpose to a specific
independence pair.

This is the property that catches negation bugs, dropped clauses, swapped
operands, and operator-precedence errors - the single-fault classes that
statement, branch, and condition coverage all leave a plausible test author free
to miss.

## How MC/DC maps onto Perl

### Decision identification

A "decision" is a top-level boolean expression used to control flow or produce a
boolean-typed value. In Perl this means any logop or `cond_expr` that is not
itself nested inside another logop of compatible type:

- `if ($a && $b)` - the `&&` is the decision.
- `$a || $b && $c` - parsed as `$a || ($b && $c)`; the outer `||` is the
  decision; the inner `&&` is part of it.
- `($a && $b) ? $x : $y` - the `cond_expr` is the decision; `$a && $b` is its
  sole condition (composed of two atomic conditions).

Statement level has a wrinkle. A logop whose value is discarded - a sub's last
statement, an implicit return - is recorded as a decision only when its right
operand is itself a decision, as in `(A && B) || (C && D)`. When the right
operand is not a decision, such as `(A && B) || $c`, the outer operator stays a
branch (see Limitations).

### Atomic conditions

Atomic conditions are the boolean leaves: variables, comparisons, function
calls, defined-or operands. Anything that is not itself a boolean operator
combining further atomic conditions.

`$a + 1 > $b` contains one atomic condition (the `>`), not three. `foo()` is one
atomic condition.

### Short-circuit and masking

`&&`, `||`, and `//` short-circuit. When a left operand determines the outcome,
the right operand is unevaluated and its value is masked. The existing XS data
records short-circuit observations as a single row with the unevaluated side
marked X (don't care). Because X arises only from short-circuit evaluation, the
unique-cause pass uses short-circuit-aware matching: X is compatible with any
concrete value in the same column, matching the behaviour of LDRA and
VectorCAST. Without this relaxation, ordinary `$a && $b` with all paths
exercised would never satisfy the left-operand pair, since `[0, X]` could never
match `[1, 1]`. The masking fallback for coupled conditions retains the same
X-as-anything rule but additionally permits other occurrences of the coupled
atomic condition to disagree.

`xor` and `^^` do not short-circuit; their truth tables have all four rows fully
populated.

## Shared runtime infrastructure

MC/DC reuses the data and structural machinery Devel::Cover already collects for
condition coverage:

1. **Per-logop truth value collection** in `Cover.xs`'s `cover_logop`. See
   `docs/technical/branches_and_conditions.md` for the layout of the condition
   array.

2. **Composite truth tables** built by `lib/Devel/Cover/Condition_table.pm`
   (added in GH-446). Given a tree of nested logops, this module synthesises a
   single composite table by taking the cross-product of the sub-decisions'
   rows; each row is marked covered or not from the per-logop hit counts. The
   "Per-decision input-vector recording" section below explains why this
   synthesis alone is not sufficient for audit-grade MC/DC and how
   runtime-observed input vectors are layered on top. The output is the data
   structure MC/DC analysis operates on:

   ```text
   A B C |exp|hit
   --------------
   0 0 X | 0 |---
   0 1 0 | 0 |---
   0 1 1 | 1 |+++
   1 X X | 1 |+++
   ```

3. **Address-based child linking with negation propagation**, also from GH-446,
   so `not($a) && $b` and parenthesised forms link correctly to their parent
   decision.

4. **Reporter rendering** of the composite tables in `Html_minimal`,
   `Html_subtle`, `Html_crisp`, `Text2`, and `Json`.

MC/DC adds the analysis on top of this shared base, a criterion class to compute
a percentage and flag missing pairs, and the per-execution input-vector recorder
needed for audit-grade results.

## Design choice: parallel criterion, shared runtime data

MC/DC is added as a parallel criterion alongside `condition`, not as an analysis
layered onto it. Runtime data is shared - the analyser derives MC/DC from the
same condition truth tables already collected by the existing XS
instrumentation, so there is no duplicated collection - but the user-visible
interface is separate:

- `mcdc` is a distinct entry in `@Devel::Cover::DB::Criteria`.
- A separate flag bit selects it in `Cover.xs`.
- `cover -coverage mcdc` enables it independently of `-coverage condition`.
- Reports show MC/DC as its own column with its own percentage.

The reasoning:

- DO-178C, ISO 26262, and IEC 61508 audits cite MC/DC by name. A separate
  criterion preserves that handle in the DB schema and reports.
- MC/DC pair-finding is O(2^N) per decision; users may want condition coverage
  without paying the MC/DC cost on wide decisions. A separate criterion makes
  MC/DC opt-in.
- Existing CI thresholds on condition coverage do not silently change meaning
  when MC/DC is added.
- Industry tools (gcov `--mcdc`, LDRA, VectorCAST) report MC/DC as a separate
  metric alongside condition coverage.

## Per-decision input-vector recording

Per-logop hit counts are not sufficient to reproduce textbook MC/DC semantics on
composite decisions. The composite truth table for
`($is_owner && $unlocked) || $is_admin` is the cross-product of the inner `&&`'s
rows and the outer `||`'s rows: every cross-product row is marked covered iff
each sub-decision's row was hit at least once. But the cross-product mixes rows
from different test executions. The misplaced-negation bug in the worked example
survives synthesis-only analysis - the buggy implementation hits the inner `&&`
row `(1,0)` on Test 2 and the outer `||` row `(0,X,0)` on Test 4, which the
cross-product synthesises into a phantom `(T,F,F)` row that no test actually
executed. The analyser, seeing the phantom row as covered, then reports the
buggy implementation as MC/DC-satisfied.

Audit-grade MC/DC therefore needs per-execution combined-input data. `Cover.xs`
records each decision's input vector at runtime: a small stack
(`MY_CXT.decision_inputs`) tracks the active decision; `cover_logop` and
`add_condition` write each leaf's observed truth value into the current vector,
and snapshot it on short-circuit-at-root or on the same-type chain reaching the
root. Column metadata (which logop is a decision root, which leaf maps to which
column index) is computed lazily on first encounter of each CV by walking the
optree from `CvROOT`. The walk uses `op_first` / `OpSIBLING` chains rather than
`op_sibparent` to preserve the 5.20 minimum (`op_sibparent` requires
`PERL_OP_PARENT`, added in 5.22 and made default in 5.26).

`Condition_table::for_line` accepts an optional parallel array of
observed-vector hashes; when present, each synthesised row is marked `covered=1`
iff its input vector matches an observed key. Synthesised rows the runtime never
executed keep `covered=0` so the truth-table renderer still draws them - users
see the unobserved combinations as "rendered but not hit" rather than vanishing.

The runtime recorder requires `Devel::Cover::Mcdc` to be loaded as a criterion
subclass during Devel::Cover's bootstrap (via `Criterion.pm`'s runtime require
loop), placing it in the path that runs before instrumentation activates.
Coverage of `Mcdc.pm` itself is therefore obtained via `make self_cover`.
`Mcdc::Analyser` is loaded lazily from `DB.pm:_derive_mcdc` and is covered by
`make dc_cover_lib`. See `docs/technical/self-coverage.md`.

## Implementation

### Analyser

`lib/Devel/Cover/Mcdc/Analyser.pm` takes a `Condition_table::Table` (rows of
`inputs[], result, covered`) and computes MC/DC pairs. The hybrid algorithm
tries unique-cause first and falls back to masking only when unique-cause is
impossible because the condition is coupled (appears more than once in the
decision):

```text
for each column c (atomic condition):
    # First pass: short-circuit-aware unique-cause MC/DC
    for each pair of rows (r1, r2):
        if r1.inputs[c] != r2.inputs[c]
        and r1.result != r2.result
        and r1 and r2 agree on every other column
            (concrete values must match; X agrees with anything)
        and r1.covered and r2.covered:
            column c is satisfied
            break

    # Second pass: masking fallback for coupled conditions
    if c is not yet satisfied
       and c appears more than once in the decision:
        for each pair of rows (r1, r2):
            if r1.inputs[c] != r2.inputs[c]
            and r1.result != r2.result
            and other occurrences of c may disagree
            and every non-c column agrees (X agrees with anything)
            and r1.covered and r2.covered:
                column c is satisfied
                break

coverage = satisfied_columns / total_columns
```

### Criterion class

`lib/Devel/Cover/Mcdc.pm`, modelled on `Branch.pm`, stores per-decision
counters: total atomic conditions, satisfied conditions, and the missing labels.

### Integration points

- `mcdc` is a member of `@Devel::Cover::DB::Criteria` and `@Criteria_short` in
  `lib/Devel/Cover/DB.pm`.
- A `Mcdc` flag bit and a `coverage_mcdc()` XS function live in `Cover.xs`.
- `DB.pm::_derive_mcdc` runs the analyser against condition truth tables during
  `cover()` before `objectify_cover`.
- `bin/cover` accepts `-coverage mcdc` and documents it in POD.

### Report integration

Each reporter renders an MC/DC summary column and, in detail views, lists which
atomic conditions lack independence pairs. The HTML reporters share the
per-atomic-condition pill rendering; `Html_crisp` additionally splits the per-
line detail block into three internally-consistent panels (per-logop cells,
MC/DC pills, composite truth table) so each panel matches one headline
percentage.

### Tests

`tests/mcdc_basic` covers the standard short-circuit forms (`&&`, `||`, chained,
leading negation, and the mixed-precedence worked example). `tests/mcdc_xor`,
`tests/mcdc_constant_right`, `tests/mcdc_demo`, and `tests/mcdc_signatures`
exercise the distinct code paths. Internal tests live under `t/internal/mcdc_*`
and `t/internal/decision_*`.

### Documentation

MC/DC is documented here, with a user-facing section 2.5 in `Tutorial.pod`,
USAGE POD in `Devel::Cover::Mcdc`, and a `Changes` entry.

## Limitations

- Decisions with more than 16 atomic conditions are skipped by
  `Condition_table::for_line`; MC/DC inherits that limit. The bound exists
  because the truth table size grows as 2^N and becomes unwieldy.

- A statement-level logop whose value is discarded records its outer operator as
  a decision only when its right operand is itself a decision. So
  `(A && B) || (C && D)` is recorded as one unified table, but `(A && B) || $c`
  is not - the outer `||` stays a branch, and an `||` versus `&&` fault in it is
  invisible to condition and MC/DC coverage. The outer is left as a branch
  because a left-only-compound join is optree-identical to a statement modifier
  (`$c unless A && B`) and cannot be told apart. In value context the outer is
  always recorded, so this affects statement-level forms only.

- Coupled conditions (the same atomic condition appearing more than once in a
  decision, such as `($a && $b) || ($a && $c)`) are placed in a single table.
  Unique-cause is impossible under coupling, so such a decision reaches hybrid's
  masking fallback in `Mcdc::Analyser`, which reduces to demonstrating
  short-circuit-induced masking rather than direct causal independence; this
  corner is the most actively debated part of the metric in the literature.

## References

- Chilenski, J.J. and Miller, S.P. (1994). "Applicability of modified
  condition/decision coverage to software testing." *Software Engineering
  Journal* 9(5).
- Hayhurst, K.J., Veerhusen, D.S., Chilenski, J.J., Rierson, L.K. (2001). *A
  Practical Tutorial on Modified Condition/Decision Coverage*.
  NASA/TM-2001-210876.
- RTCA DO-178C (2011). *Software Considerations in Airborne Systems and
  Equipment Certification*.
- ISO 26262 (2018). *Road vehicles - Functional safety*.
- See also: `docs/technical/branches_and_conditions.md` for the underlying
  condition-coverage data layout, and `lib/Devel/Cover/Condition_table.pm` for
  the composite truth-table builder MC/DC builds on.

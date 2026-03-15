# Branch and Condition Coverage

Devel::Cover tracks two related but distinct coverage criteria for
logical operators: **branch** coverage and **condition** coverage. This
document explains what each measures, how the classification is
determined, and how the runtime data flows from the XS layer through to
the Perl-level reporting.

## Overview

Branch and condition coverage both deal with logical operators (`&&`,
`||`, `and`, `or`, `?:`, `xor`, `^^`, `//`), but they answer different
questions:

- **Branch coverage** asks: "Was each path through this decision taken?"
  A branch has two outcomes (true/false) and is 100% covered when both
  paths have been exercised.

- **Condition coverage** asks: "What combinations of operand truth
  values were observed?" A two-operand condition has 2 or 3 possible
  outcomes depending on the operator and context; a four-operand `xor`
  has 4.

The same underlying runtime data (collected in `Cover.xs`) feeds both
metrics. The Perl-level code in `lib/Devel/Cover.pm` determines which
metric to register for each op based on how the op is used.

## The Classification Rule

The central question is: does a logical op represent a **control flow
decision** (branch) or a **value computation** (condition)?

### Branches

A logical op is classified as a branch when it controls which code path
executes and its return value is not used. This includes:

| Source form                | Deparse           | Why branch      |
| -------------------------- | ----------------- | --------------- |
| `if ($x) { ... }`          | `if ($x) { }`     | Block statement |
| `$y++ if $x`               | `if $x`           | Statement mod   |
| `$x && $y++` (at stmt lvl) | `$x and ++$y` \*  | Void context    |
| `$x \|\| next`             | `$x or next` \*   | Void context    |
| `unless ($x) { ... }`      | `unless ($x) { }` | Block statement |
| `$x ? $a : $b`             | `$x ? :`          | Ternary         |
| `if ($x) { } elsif { }`    | `if ($x) { }`     | Chain           |

\*On Perl 5.43.8+, expression-form logops at statement level keep their
expression-form labels (`$x and ++$y`, `$x or next`). On older Perls,
they get statement-modifier labels (`if $x`, `unless $x`) because the
optree cannot distinguish the two forms.

The ternary (`?:` / `cond_expr`) is always branch coverage regardless
of context, because it always has two distinct code paths (true block
and false block).

### Conditions

A logical op is classified as a condition when its return value is used
as part of a larger expression:

| Source form              | Deparse          | Why condition     |
| ------------------------ | ---------------- | ----------------- |
| `my $z = $x && $y`       | `$x && $y`       | Value is assigned |
| `foo($x \|\| $y)`        | `$x \|\| $y`     | Value is passed   |
| `$x && $y` inside `if()` | `$x and $y`      | Nested in branch  |
| `$p &&= $y`              | `$p &&= $y`      | Assign-through    |
| `$x // $default`         | `$x // $default` | Value is used     |

### Compound assignment operators

`&&=`, `||=`, and `//=` are always condition coverage. They are handled
by `logassignop`, which unconditionally calls `add_condition_cover`.

### The `xor` operator

`xor` (and `^^` from 5.42+) is always condition coverage with 4
outcomes: `l&&r`, `l&&!r`, `!l&&r`, `!l&&!r`.

## How Classification Works in Code

### `logop` - the `&&`/`||`/`and`/`or` handler

The `logop` function in `lib/Devel/Cover.pm` is the monkey-patched
replacement for `B::Deparse::logop`. It receives a context parameter
`$cx` and an optional `$blockname` (`"if"` for `and` ops, `"unless"`
for `or` ops).

The function has four branches that determine both the deparse format
and the coverage type:

```text
Case 1: $is_statement && is_scope($right)
        -> deparse: "if ($left) { $right }"
        -> BRANCH coverage

Case 2: $is_statement && ...
        -> deparse: "$right if $left"
        -> BRANCH coverage

Case 3: $cx > $lowprec && $highop
        -> deparse: "$left && $right"
        -> CONDITION coverage

Case 4: else
        -> deparse: "$left and $right"
        -> BRANCH if $is_branch, CONDITION otherwise
```

Two variables control the split:

- **`$is_statement`** determines deparse format (statement modifier
  vs expression form). On 5.43.8+ it reflects `OPpSTATEMENT` only.
  On older Perls it uses B::Deparse's heuristic.

- **`$is_branch`** determines coverage classification. It is true
  whenever `$is_statement` is true, and also for statement-level
  expression-form logops (`$cx < 1 && $blockname`).

```perl
my $is_statement
  = Has_op_statement()
  ? $op->private & OPpSTATEMENT()
  : $cx < 1 && $blockname && $self->{expand} < 7;

my $is_branch = $is_statement || ($cx < 1 && $blockname);
```

On 5.43.8+, this separation means expression-form logops at statement
level (e.g. `$y && $x++`) fall through to case 4, where they get
expression-form labels (`$y and ++$x[5]`) but are still classified as
branch coverage because `$is_branch` is true. On older Perls,
`$is_statement` and `$is_branch` are always equal (both use the same
heuristic), so cases 1/2 handle all statement-level logops with
statement-modifier labels (`if $y`).

The `$cx < 1` test means we are at statement level (the return value
is discarded). `$blockname` being set means the op has a
statement-form keyword (`if`/`unless`). Together they identify logops
that are semantically branches.

### `_cover_cond_expr` - the `?:` / `if-else` handler

The `cond_expr` op covers both ternary expressions and if/else
statements. Both forms always get **branch** coverage - the
`$is_statement` flag only determines the label format:

- Statement form: `"if ($cond) { }"` with elsif chain walking
- Expression form: `"$cond ? :"`

On 5.43.8+, `OPpSTATEMENT` determines the label. On older Perls, the
heuristic examines the structure of the true and false blocks.

### `logassignop` - the `&&=`/`||=`/`//=` handler

Always calls `add_condition_cover`. These are value-producing
operations (they assign the result), so condition coverage is
appropriate.

### `binop` - the `^^` handler (5.42+)

Perl 5.42 added `^^` as the high-precedence form of `xor`. Unlike
`xor` (which is an `OP_XOR` logop handled by the runtime's
`cover_logop`), `^^` compiles as a `binop`. The monkey-patched
`binop` function intercepts `^^` (and `xor` from 5.42+) and calls
`add_condition_cover` before delegating to the original `binop`.

## Runtime Data Collection (Cover.xs)

The XS layer collects raw counts for every logical op at runtime. This
data feeds both branch and condition coverage at the Perl level.

### The condition array

Each logical op has a 6-element array stored in `$Coverage->{condition}`
keyed by op address. The indices track different outcomes:

```text
Index   Meaning
-----   -------
  0     Flag: first operand of xor was true (internal bookkeeping)
  1     Count: left false, right not evaluated (short-circuited)
  2     Count: left true, right false (not short-circuited)
  3     Count: left true, right true (not short-circuited)
  4     Count: left true, right true (xor-specific)
  5     Flag: void context (the RHS is a control flow op)
```

### How the XS code collects data

1. **`cover_logop`** runs when a logical op (`OP_AND`, `OP_OR`,
   `OP_XOR`, `OP_DOR`, and their assign variants) is about to execute.
   It checks the truth value of the left operand on the stack.

2. If the op short-circuits (left is false for `and`, true for `or`),
   `add_conditional` immediately records the outcome at index 3
   (left determined the result).

3. If the op does not short-circuit, `cover_logop` needs to see the
   right operand's value too. It installs a temporary hook
   (`get_condition`) at the op that follows the right operand. When
   execution reaches that op, `get_condition` examines the stack and
   records the outcome at index 1 (right was false) or 2 (right was
   true).

4. **Void context shortcut**: if the op is in void context, or the
   right operand is a control flow op (`next`, `last`, `redo`, `goto`,
   `return`, `die`), the right operand's truth value is irrelevant. The
   XS code records a 2-outcome result immediately instead of waiting
   for `get_condition`.

5. **`finalise_conditions`** runs after the programme finishes. Any
   pending conditions that were never resolved (e.g., because of an
   early `return` before the right operand's follow-on op was reached)
   are collected here.

### `cover_cond` - branch data from `cond_expr`

The `cond_expr` op (`?:` / `if-else`) uses a simpler mechanism.
`cover_cond` runs at the `cond_expr` op and records which branch
(true or false) was taken, using `add_branch` directly.

## How the Perl Layer Interprets Raw Data

The raw condition array from the XS layer is reinterpreted by
`add_branch_cover` and `add_condition_cover` in `lib/Devel/Cover.pm`.

### `add_branch_cover`

For `and`/`or` type branches (where branch coverage is derived from
condition data), the function reads from `$Coverage->{condition}{$key}`
and collapses the 6-element array into 2 values:

```perl
# True path = left true and right evaluated (indices 1 + 2)
# False path = short-circuited (index 3)
$c = [ $c->[1] + $c->[2], $c->[3] ];
```

For `if`/`elsif` type branches, the function reads from
`$Coverage->{branch}{$key}`, which is populated directly by
`cover_cond` in the XS layer with a simple `[true_count, false_count]`.

### `add_condition_cover`

Reorders the raw array into human-readable columns depending on the
operator and the number of outcomes:

**`and` with 3 outcomes** (both operands can be independently true or
false):

```perl
# Columns: !l, l&&!r, l&&r
@$c = @{$c}[3, 1, 2];
```

**`or` with 3 outcomes**:

```perl
# Columns: l, !l&&r, !l&&!r
@$c = @{$c}[3, 2, 1];
```

**`and`/`or` with 2 outcomes** (when the right operand is a constant or
control flow op like `next`, `die`, `return`):

```perl
# Columns: l, !l
$c = [ $c->[3], $c->[1] + $c->[2] ];
```

The right operand's truth value does not matter in this case, so only
two outcomes are tracked. The `$Const_right` pattern determines this:

```perl
my $Const_right = qr/^(?:const|s?refgen|gelem|die|undef|
    bless|anon(?:list|hash)|emptyavhv|scalar|
    return|last|next|redo|goto)$/x;
```

**`xor` with 4 outcomes**:

```perl
# Columns: !l&&!r, l&&!r, l&&r, !l&&r
@$c = @{$c}[3, 2, 4, 1];
```

## The Condition Criterion Classes

Each combination of operator and outcome count has a corresponding
class in `lib/Devel/Cover/`:

| Class             | Operator | Outcomes | Headers                |
| ----------------- | -------- | -------- | ---------------------- |
| `Condition_and_2` | and/&&   | 2        | `l`, `!l`              |
| `Condition_and_3` | and/&&   | 3        | `!l`, `l&&!r`, `l&&r`  |
| `Condition_or_2`  | or/\|\|  | 2        | `l`, `!l`              |
| `Condition_or_3`  | or/\|\|  | 3        | `l`, `!l&&r`, `!l&&!r` |
| `Condition_xor_4` | xor/^^   | 4        | `l&&r`, `l&&!r`, etc.  |

The `type` field in the condition structure (e.g. `"and_3"`, `"or_2"`)
selects the class at report time.

## OPpSTATEMENT (Perl 5.43.8+)

Perl 5.43.8 added the `OPpSTATEMENT` private flag to logical ops. When
set, it means the op was written in statement form (`$x++ if $y`,
`if ($x) { ... }`, `next unless $y`). When not set, it was written in
expression form (`$x && $y`, `$x and $y`).

Devel::Cover imports this flag conditionally:

```perl
BEGIN {
  my $v = $] >= 5.043008 ? 1 : 0;
  *Has_op_statement = sub () { $v };
  B->import("OPpSTATEMENT") if $v;
}
```

The constant sub `Has_op_statement` is a compile-time-foldable boolean
that gates all OPpSTATEMENT checks. It must be called with explicit
parentheses (`Has_op_statement()`) because on Perl 5.20 the bare form
`Has_op_statement ?` is parsed as the deprecated match-once `?PATTERN?`
operator.

### Where OPpSTATEMENT is used

1. **`logop`**: determines deparse format (statement modifier vs
   expression). A separate `$is_branch` variable combines
   `$is_statement` with `$cx < 1 && $blockname` to also classify
   statement-level expression-form logops as branches.

2. **`_cover_cond_expr`**: determines whether to label as
   `"if ($cond) { }"` (with elsif walking) or `"$cond ? :"`. Both
   forms are always branch coverage.

### Why statement-level expression logops are branches

Consider `$y && $x++` at statement level. Perl 5.43.8 does not set
OPpSTATEMENT on this op because the programmer wrote it in expression
form. But the return value is discarded (void context). Semantically
this is identical to `$x++ if $y` - we care about whether the path was
taken, not about the combined truth value of `$y && $x++`.

If classified as condition coverage, the report would show 2 or 3
condition outcomes for `$y and ++$x`, which is misleading - the truth
value of `$x++` is irrelevant. Branch coverage with a simple
true/false outcome is the appropriate metric.

On 5.43.8+, because `$is_statement` only reflects `OPpSTATEMENT`, the
expression-form logop falls through to case 4 of `logop` and gets an
expression-form label (`$y and ++$x[5]`). The `$is_branch` variable
ensures it is still classified as branch coverage despite not being in
statement form.

On older Perls, both forms are indistinguishable in the optree, so
both get the statement-modifier label (`if $y`).

The XS layer's void-context detection already handles this at the data
level (recording only 2 outcomes when in void context), so the Perl
layer's classification aligns with what the runtime actually measured.

## Examples

### Branch: `$y && $x++` at statement level

```perl
$y && $x++;   # void context - branch coverage
```

Report output on 5.43.8+:

```text
Branches
line  err      %   true  false   branch
28    ***     50      0      4   $y and ++$x[5]
```

On older Perls (before 5.43.8):

```text
Branches
line  err      %   true  false   branch
28    ***     50      0      4   if $y
```

Two outcomes: `$y` was true (path taken) or false (short-circuited).
The label format differs but the coverage data is identical.

### Branch: `if ($x) { } elsif ($y) { } else { }`

```perl
if ($x) {     # branch: if ($x) { }
    ...
} elsif ($y) {  # branch: elsif ($y) { }
    ...
} else {
    ...
}
```

Each decision point is a separate branch entry with true/false counts.

### Condition: `$x && $y` inside an `if`

```perl
if ($x && $y) { ... }
```

The `if` itself is a `cond_expr` op and gets **branch** coverage
(`if ($x && $y) { }`). The `&&` inside the condition is a nested logop
with `$cx > 0`, so it gets **condition** coverage with 3 outcomes:

```text
Conditions
and 3 conditions
line  err      %     !l  l&&!r   l&&r   expr
17    ***     33      4      0      0   $x and $y
```

### Condition: `$p &&= $y`

```perl
$p &&= $y;   # always condition coverage (logassignop)
```

Report output:

```text
Conditions
and 3 conditions
line  err      %     !l  l&&!r   l&&r   expr
41    ***     33     11      0      0   $p &&= $y
```

### Condition with 2 outcomes: `$y || die`

```perl
$y || die "oops";   # void context, but die is a const-right op
```

When the right operand matches `$Const_right` (which includes `die`),
condition coverage uses 2 outcomes because the right operand's truth
value is not meaningful:

```text
Conditions
or 2 conditions
line  err      %      l     !l   expr
280          100      4      2   $x || die()
```

## Test Files

The primary test files for branch and condition coverage are:

- `tests/cond_branch` - exercises the branch/condition boundary:
  `$y && $x++` vs `$x++ if $y`, `$y || next`, loop control operators,
  `goto`, `redo`, ternary, if/elsif chains, and compound conditions.
- `tests/cond_and` - focuses on `&&`/`and` in various contexts
  including `&&=`.
- `tests/cond_or` - focuses on `||`/`or`/`//` and `||=`/`//=`.

Golden output files in `test_output/cover/` serve as regression tests.

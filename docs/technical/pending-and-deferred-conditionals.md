# Pending and Deferred Conditionals

When a logical operator like `||` does not short-circuit, Devel::Cover needs to
see the right operand's value before it can record the condition outcome. Two
mechanisms handle this, depending on whether there is a subsequent op to
intercept.

`Pending_conditionals` is the normal mechanism: it hijacks the op that follows
the right operand and reads the stack when that op is reached.

`deferred_conditionals` handles the case where there is no subsequent op to
hijack - specifically, sort block comparators where the final op's `op_next` is
NULL.

Both feed into the same condition array (slots [1] and [2]) and ultimately
produce the same branch and condition coverage data.

## Background: the condition array

Each logical op has a 6-element condition array (see
`branches_and_conditions.md` for the full layout). The slots relevant here are:

```text
[1]  not short-circuited, right operand was false
[2]  not short-circuited, right operand was true
[3]  short-circuited (left operand determined the result)
```

The short-circuit path (slot [3]) is straightforward: `cover_logop()` records it
immediately via `add_conditional(op, 3)` because the left operand's value is
known at the time the logical op is despatched. No deferred work is needed.

The non-short-circuit path (slots [1] and [2]) is harder: the right operand
hasn't been evaluated yet. Devel::Cover must wait until the right operand
finishes, then read its value to decide between slot [1] (false) and slot [2]
(true).

## Pending_conditionals: the hijack mechanism

`Pending_conditionals` is a global HV (process-wide, protected by `DC_mutex` in
threaded builds). It stores condition data that is waiting for a specific op to
be reached.

### How it works

When `cover_logop()` handles the non-short-circuit path:

1. It finds the op that will execute after the right operand:
   `next = right->op_next` (skipping any OP_NULL nodes).

2. It creates (or reuses) an entry in `Pending_conditionals` keyed by `next`'s
   address. The entry is an AV containing:

   - `[0]` the target op pointer (`next`)
   - `[1]` the original `op_ppaddr` of `next`
   - `[2+]` the logical ops waiting for resolution at this target

3. It replaces `next->op_ppaddr` with `get_condition` (or `get_condition_dor`
   for `//` operators).

4. When the normal Perl execution loop reaches `next`, it calls the hijacked
   `op_ppaddr`, which is now `get_condition`.

5. `get_condition()` reads `TOPs` (the stack top, which holds the right
   operand's value), calls `add_condition()` to record slot [1] or [2] for each
   pending logical op, restores the original `op_ppaddr`, and returns `PL_op` so
   the hijacked op runs normally.

Multiple logical ops can share the same target. For example, in
`$a || $b || $c`, when `$a` is false and `$b` is also false, both `||` ops are
waiting on the same `next` op (the one after `$c`). They are all stored in the
same `Pending_conditionals` entry and resolved together.

### Limitations

The mechanism relies on `right->op_next` being non-NULL. There must be an op to
hijack. This works in the vast majority of cases because most code has a
continuation op after any expression. However, it fails when `right->op_next` is
NULL, which happens in two known cases:

- **Compile-time constant folding**: the op tree was simplified away. This was
  the original reason for the bail-out, noted in the comment
  `/* in fold_constants */`.

- **Sort block comparators**: the ops inside a sort block have NULL `op_next`
  pointers because `pp_sort` reads the result directly from the stack. There is
  no continuation op.

### Where to find it in Cover.xs

- Declaration: line ~148 (`static HV *Pending_conditionals`)
- Setup in `cover_logop()`: lines ~1248-1278 (hv_fetch, av_push, ppaddr
  replacement)
- Resolution in `get_condition()`: lines ~1048-1069
- End-of-run cleanup in `finalise_conditions()`: lines ~1092-1115

## deferred_conditionals: the runops-exit mechanism

`deferred_conditionals` is a per-thread AV stored in `my_cxt_t`. It holds OP
pointers for conditions that could not be hijacked because `right->op_next` was
NULL.

### Why sort blocks have NULL op_next

Sort blocks are special in Perl's internals. The op tree for a sort comparator
like:

```perl
sort { $b->{cnt} <=> $a->{cnt} || $a->{val} cmp $b->{val} } @data
```

looks like:

```text
or(other->-) sK/1 ->(end)     # or's op_next is NULL
   ncmp[t6] sK/2 ->-
   scmp[t9] sK/2 ->(end)      # right's op_next is NULL
```

The `(end)` notation means `op_next` is NULL. `pp_sort` invokes the comparator
via `CALLRUNOPS`, which runs the ops until PL_op becomes NULL. `pp_sort` then
reads the result directly from `*PL_stack_sp`. There is nowhere for the ops to
"go next" because `pp_sort` handles the transition.

### How it works

1. In `cover_logop()`, when `right->op_next` is NULL (after skipping OP_NULLs),
   instead of bailing out, we push the current op onto
   `MY_CXT.deferred_conditionals`:

   ```c
   av_push(MY_CXT.deferred_conditionals, newSViv(PTR2IV(PL_op)));
   ```

2. The original `pp_or` then executes, falls through to the right operand, and
   the right operand runs. When the right operand's final op returns NULL, the
   runops loop exits.

3. At the runops loop exit (in both `runops_cover` and `runops_orig`),
   `resolve_deferred_conditionals()` is called. It checks for entries pushed
   during this invocation (from `deferred_base` upwards). The stack top at this
   point holds the sort comparator's final value - the right operand of the
   outermost `||`. The function reads `SvTRUE(TOPs)` to decide between slot [1]
   (right false) and slot [2] (right true), then pops and resolves each deferred
   entry via `add_conditional`.

4. The result is identical to what `get_condition` would record for the normal
   hijack path.

### Why only the outermost || is affected

For chained comparators like `A || B || C`, Perl compiles this as
`(A || B) || C`. The inner `||`'s right operand (`B`) has `op_next` pointing to
the outer `||` - a valid, non-NULL op. So the normal hijack mechanism works for
inner `||` nodes. Only the outermost `||` (whose right operand's `op_next` is
NULL because it is the sort block's final value) triggers the deferred path.

This means there is exactly one deferred entry per sort comparator invocation.
The stack value at runops exit is the right operand's value for that outermost
`||`.

### The deferred_base guard

Each invocation of `runops_cover` or `runops_orig` saves the current length of
the deferred array on entry:

```c
I32 deferred_base = av_len(MY_CXT.deferred_conditionals) + 1;
```

On exit, it only processes entries from `deferred_base` upwards - entries pushed
during this invocation. This guard handles two scenarios:

**Nested sorts.** `pp_sort` calls `CALLRUNOPS` for each comparison. If a sort
comparator itself contains another sort, the call stack becomes:

```text
runops (outer comparison)       deferred_base = 0
  cover_logop pushes entry      array = [op_outer]
  pp_sort (inner) calls runops
    runops (inner comparison)   deferred_base = 1
      cover_logop pushes entry  array = [op_outer, op_inner]
    inner runops exit:          resolves op_inner (index 1)
                                array = [op_outer]
  outer runops exit:            resolves op_outer (index 0)
                                array = []
```

Without the guard, the inner runops would resolve `op_outer` using the inner
sort's stack value.

**Exceptions.** If a sort comparator dies (e.g., via a function call that
throws), the longjmp bypasses the runops loop exit. Deferred entries from the
failed comparator remain in the array. When the next sort runs (after eval
catches the exception), `deferred_base` is set past the stale entries, so they
are ignored:

```text
eval {
  sort { ... || boom() } @data   # boom() dies
  # cover_logop pushed entry, die skipped loop exit
  # array = [stale_op]
};
# now array still has [stale_op]

sort { ... || ... } @other       # deferred_base = 1
# new entries at index 1+, only those are resolved
```

The stale entries remain in the array for the lifetime of the program but are
harmless - they are small SVs holding OP pointers that are never dereferenced.

### Thread safety

`deferred_conditionals` is per-thread (`MY_CXT`), so no mutex is needed. The
push in `cover_logop` and the resolution in the runops functions all operate on
the same thread's data.

### Dual runops support

Devel::Cover has two execution modes:

- **runops_cover mode**: `PL_runops` is set to `runops_cover`, which provides a
  full despatch loop with coverage collection in a switch statement.

- **replace_ops mode**: individual op ppaddr functions are replaced with `dc_*`
  wrappers (e.g., `dc_or` wraps `pp_or`). The runops loop is Devel::Cover's
  `runops_orig`, a lightweight loop.

The deferred resolution code is present in both `runops_cover` and `runops_orig`
so that it works regardless of mode. In replace_ops mode, `PL_runops` is set to
`runops_orig` to ensure the resolution code is reached.

### Where to find it in Cover.xs

- Field declaration: `my_cxt_t.deferred_conditionals` (line ~140)
- Initialisation in `initialise()`: `MY_CXT.deferred_conditionals = newAV()`
  (line ~1537)
- Push in `cover_logop()`: the `if (!next)` block (lines ~1253-1260)
- Helper: `resolve_deferred_conditionals()` (line ~1134)
- Call from `runops_cover()`: loop exit (line ~1657)
- Call from `runops_orig()`: after the while loop (line ~1687)
- Boot: `PL_runops = runops_orig` in replace_ops branch (line ~1967)

## Comparison

| Aspect           | Pending_conditionals   | deferred_conditionals  |
| ---------------- | ---------------------- | ---------------------- |
| Trigger          | Hijacked op despatched | runops loop exits      |
| Storage          | Global HV (with mutex) | Per-thread AV          |
| Key              | Target op address      | Array index            |
| Multiple pending | Yes (share one hijack) | Yes (resolved at exit) |
| Requires op_next | Yes                    | No                     |
| Use case         | Normal logop code      | Sort block logops      |

## Test coverage

The `tests/sort_or` test script exercises the deferred mechanism with six cases:

- Cases 1-2: basic sort blocks with `||` (fall-through and mixed)
- Case 3: ternary in sort block (control, uses `cover_cond`)
- Case 4: nested sorts with `||` (tests `deferred_base` guard)
- Case 5: exception in sort comparator via function call (tests that stale
  deferred entries don't corrupt state)
- Case 6: sort after exception (tests `deferred_base` skips stale entries)

Golden output: `test_output/cover/sort_or.<version>`

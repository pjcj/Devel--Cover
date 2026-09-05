# Outer Lexicals Captured by Special Blocks

A `BEGIN`, `UNITCHECK`, `CHECK` or `INIT` block that uses a lexical from an
enclosing scope captures it in the block's own pad, as any closure does. The pad
entry holds a reference, so the variable cannot be freed while the block's CV
lives.

Perl frees a `BEGIN` CV as soon as it has run. Devel::Cover cannot allow that,
because the report reads every special block at `END` time to map the counts
collected at run time back to lines. So `Cover.xs` sets `PL_savebegin` at boot,
which makes `Perl_call_list` push each `BEGIN`, `CHECK` and `UNITCHECK` CV onto
`PL_beginav_save` and its siblings instead of freeing it. `INIT` CVs are neither
saved nor freed under that flag, so they leak.

The side effect, reported as GH-118, is that a variable captured by a special
block lives until global destruction. A scope guard created in a `BEGIN` block
and stored in a lexical of the enclosing block ran its `DESTROY` after the `END`
blocks rather than at the end of the enclosing block. A `my` declared inside the
block is not affected, since scope exit clears it. Only captured outer lexicals
are.

## The report's needs

The `END` time report reads the block's op tree and its pad names. B::Deparse
reads pad values only from unnamed slots and from lexical sub slots, whose names
start with `&`. Unnamed slots hold constants and GVs on perls built with
ithreads, and anon sub prototypes everywhere. The values of captured outer
lexicals are never read. Once the block has run, nothing needs them.

## The fix

When a special block is left, `note_finished_block` in `Cover.xs` queues its CV.
At the next statement `release_finished_blocks` drains the queue. For each CV
`release_captured_pad` drops every pad slot whose name is an outer capture
(`PadnameOUTER`), is not an `our` declaration and does not start with `&`, and
stores `&PL_sv_undef` in the slot. Everything else in the pad stays, and the CV
itself stays on the saved array for the report.

The outer scope still owns its variable, so dropping the block's reference
changes nothing until that scope ends. At that point the variable is freed as it
would be without coverage. No Perl code runs between a block returning and the
next statement, so the timing matches plain perl for `BEGIN`.

The queue is drained by popping rather than iterating, since a `DESTROY` run by
the release may execute statements and re-enter the drain. The empty queue test
is a single inline comparison per statement.

## Block exit as the signal

A first version used the saved arrays directly, treating a CV with `CvDEPTH`
zero as finished. That crashed under a debugger. With `$^P` set, `Perl_call_sv`
marks its `entersub` with `OPpENTERSUB_DB`, so every special block is called
through `DB::sub`, which runs a statement between perl pushing the CV onto the
saved array and entering it. The block's captured variables were released before
it ran, and Errno.pm's `BEGIN` then wrote into a read-only undef. Neither the
arrays nor the depth can tell a finished block from one about to start. The
block's own `leavesub` or `return` can, and Devel::Cover sees both in either op
mode. In replace mode `dc_leavesub` and `dc_return` do the queueing. In the
runops loop the two op types join the existing op type checks.

## Known deviations from plain perl

Plain perl frees `UNITCHECK`, `CHECK` and `INIT` CVs at the unwind of the scope
that ran them. For the main program that is the end of the run, just before the
`END` blocks. For a required file that is the end of the require. Devel::Cover
releases their captures at block exit instead, so a variable captured by one of
these blocks is freed when its own scope ends. Matching perl exactly would need
the savestack position of a call Devel::Cover cannot hook, and code that depends
on the later timing is rare.

A `BEGIN` block inside a string eval that captures a lexical from outside the
eval is still delayed. The `BEGIN` CV holds a strong `CvOUTSIDE` reference to
the eval CV, whose pad holds the captured entry, and the saved `BEGIN` keeps
that chain alive. Weakening the pointer would leave the report with a dangling
reference once perl freed the eval CV, so the case is left alone and documented
under LIMITATIONS in `Devel::Cover.pod`.

## Tests

`t/internal/special_block_lexicals.t` runs a fixture plain and under coverage in
both op modes and compares the printed destruction order. It covers the reported
case, a `BEGIN` inside a sub, a `BEGIN` that exits through `return`, a file
lexical captured in a required module, and the reported case under a `DB::sub`
stub. A second fixture asserts the block exit behaviour for `UNITCHECK`, `CHECK`
and `INIT`.

# Missing Coverage for Top-Level Module Statements

When a module is loaded with `require` or `use`, Devel::Cover collects no
coverage at all for the statements, branches and conditions in the module's
top-level code (the code outside any subroutine). The lines are not reported as
uncovered. They are simply absent from the coverage structure, which inflates
the reported percentages. A module whose subs are fully exercised reports 100%
statement coverage even if half its top-level code never ran.

The tests `t/internal/module_top_level.t` and `tests/module_require` guard
against this. Before the fix the golden results showed `Module_top_level.pm` at
100% with every top-level line blank, the same deficiency that sat in the golden
results of `module1` and friends for years (lines 10 and 11 of `Module1.pm`).

## Why the data is lost

Devel::Cover collects coverage in two phases.

1. At run time the replaced ops record execution counts into hashes keyed by op
   address plus an identity hash of the op's fields (`get_key` in `Cover.xs`).
2. At `END` time `Devel::Cover::report` walks op trees with `B` to map each key
   back to a file and line, and builds the structure. It walks
   `B::main_cv`/`B::main_root`, the saved `BEGIN`/`CHECK`/`UNITCHECK` blocks,
   `INIT`/`END` blocks, and every named-sub CV found through the symbol table.

The top-level code of a required file appears in none of those places. The
run-time counts are collected, but at `END` time there is no op tree left to
walk, so the keys can never be mapped and the statements never enter the
structure.

The precise reason, from the perl source (blead, and unchanged in spirit since
5.000), is a known wart. `S_process_optree` in `op.c` notes

> XXX for some reason, evals, require and main optrees are never attached to
> their CV; instead they just hang off PL_main_root + PL_main_start or
> PL_eval_root + PL_eval_start and get manually freed when appropriate

In detail, for a successful require:

- `S_doeval_compile` (`pp_ctl.c`) creates an eval CV (`CvEVAL_on`) but the
  compiled ops are never attached to it. `CvROOT` and `CvSTART` stay NULL. The
  tree hangs off `PL_eval_root`/`PL_eval_start`.
- On successful compilation `doeval_compile` schedules
  `SAVEFREEOP(PL_eval_root)` on the require's eval scope and calls
  `cv_forget_slab(evalcv)`, so the ops own their opslab themselves.
- When the file's top-level code finishes, `pp_leaveeval` unwinds that scope and
  the `SAVEFREEOP` fires `op_free(PL_eval_root)`. The whole top-level tree,
  including every `nextstate` COP, is freed at that moment, long before `END`.
- The eval CV itself usually survives to program end as an empty husk. Every
  named sub compiled in the file holds a strong `CvOUTSIDE` reference to it (the
  weakening in `newATTRSUB` is skipped when the outside CV is an eval CV). But
  since `CvROOT` is NULL the husk gives `B` no route to the ops.
- Each sub compiled in the file has its own opslab owned via its own `CvROOT`,
  which is why sub bodies are covered normally and only the top-level code is
  lost.

`BEGIN` blocks in the module are covered because of an existing keep-alive
mechanism. `Cover.xs` sets `PL_savebegin = TRUE` at boot, which makes
`Perl_call_list` push executed `BEGIN`/`CHECK`/`UNITCHECK` CVs onto
`PL_beginav_save`/`PL_checkav_save`/`PL_unitcheckav_save` instead of freeing
them, and `B::begin_av` exposes the saved array. That mechanism was added for
the compiler backends and is precisely the precedent for a fix.

No existing `$^P` flag helps. `PERLDBf_SAVESRC` and friends retain source text,
not ops. `DB::postponed` receives the file GV only. String eval is affected in
exactly the same way as require.

## How it could be solved

### Option A: a core mechanism to save require optrees

Follow the `PL_savebegin` precedent. Add to core perl:

- a boolean interpreter variable, say `PL_savereqtree`, set by an XS-visible API
  in the same way `B::save_BEGINs` sets `PL_savebegin` (or a new `$^P` bit, say
  `PERLDBf_SAVEEVALTREE`, for non-XS users),
- in `S_doeval_compile`, when the flag is on and compilation succeeded, attach
  the tree to the CV instead of scheduling its death. That is, set
  `CvROOT(evalcv) = PL_eval_root` and `CvSTART(evalcv) = PL_eval_start`, skip
  the `SAVEFREEOP(PL_eval_root)`, and push a refcounted reference to the CV onto
  a new save array, say `PL_evalav_save`,
- free the array in `perl_destruct` next to `PL_beginav_save`, and dup it in
  `perl_clone` (`sv.c`),
- a `B::eval_av` accessor aliased to `PL_evalav_save` exactly as `B::begin_av`
  is aliased to `PL_beginav_save`.

Attaching the root to the CV means the normal CV destruction path
(`cv_undef_flags`) frees the tree, so no separate bookkeeping is needed, and
`B::CV::ROOT`/`START` work on the saved CVs without further changes. The eval
root already carries `OPpREFCOUNTED` with a refcount of 1, matching what
`cv_undef_flags` expects of a `CvROOT`.

Devel::Cover would then enable the flag at boot next to `PL_savebegin` and walk
`B::eval_av` in `_report` next to the `begin_av` walk. The eval CV's pad
(holding the file's lexicals) survives with it, so deparsing branch and
condition text works as for any other CV.

Points to settle in the core design:

- whether the flag covers require only or string evals too. Both are lost today.
  Saving every string eval of a long-running program could cost real memory, so
  either restrict to require (`CxOLD_OP_TYPE == OP_REQUIRE`, known from
  `in_require` at compile time) or use two bits.
- failed requires and compile failures must not be saved (the existing error
  paths free `PL_eval_root` and must stay untouched).
- memory is otherwise modest for require, one optree and CV per loaded file, the
  same order as the subs in those files, and only when a debugging tool asks for
  it.
- `CvDEPTH` and reuse do not arise. The saved CV is never called again.

### Option B: Devel::Cover-only mitigation on existing perls (implemented)

Core `op_free` on a refcounted root (`OP_LEAVEEVAL` is in the switch in
`Perl_op_free`) merely decrements the refcount and returns if it stays non-zero.
So an extension can keep a require's optree alive today. This is what
Devel::Cover now does:

- `dc_leaveeval` hooks `PL_ppaddr[OP_LEAVEEVAL]` in `replace_ops`, with the same
  capture in the `runops_cover` loop for `-replace_ops 0`,
- `capture_require_tree` fires when the current context is `CXt_EVAL` with
  `CxOLD_OP_TYPE == OP_REQUIRE` and `check_if_collecting` accepts the file. It
  takes `OpREFCNT_inc` on `PL_op` (which at that moment is `PL_eval_root`, the
  root of the file's top-level tree), takes a reference to the husk CV from
  `cx->blk_eval.cv` for deparse context, and stashes CV, root address and
  `CopFILE(PL_curcop)` in `MY_CXT.require_trees`,
- `dc_return` hooks `PL_ppaddr[OP_RETURN]` for the same reason, since a
  top-level `return` makes `pp_return` unwind the eval and tail-call
  `pp_leaveeval` directly without dispatching the leaveeval op. It mirrors
  `dopoptosub_at` to find the context being unwound and captures the tree from
  `PL_eval_root` when that context is a require,
- the scheduled `SAVEFREEOP` then only decrements the refcount,
- at report time `_report` fetches the triples via `get_require_trees` and walks
  each with `get_cover($cv, $root)`, exactly as `main_cv`/`main_root` is walked.
  Since there is no `set_subroutine` call for top-level code, the walk first
  establishes the structure's file context with `set_file`, or the per-file
  statement counters would run against whichever file the CV walk touched last
  (`set_file` is idempotent for the digest list to allow this),
- `release_require_trees` frees the trees after the report, nulling `PL_comppad`
  around `op_free` as `cv_undef` does, because pad ops free their pad slots
  against the current pad, which by then belongs to something else. It is
  idempotent since `report` can run more than once.

This needs no core change and works back to 5.20, threaded and unthreaded, at
the cost of holding the trees in memory for the run, which is what Option A does
too. It relies on `PL_op` being the eval root inside the leaveeval pp hook, on
`PL_eval_root` being that root at a top-level return, on the refcount semantics
of `op_free`, and on the husk CV's pad remaining valid, none of which are
documented guarantees. It also misses requires that die part way through, where
`pp_leaveeval` never runs, though those trees are freed during the die unwinding
anyway, so nothing can be done about them without core support.

String evals that perform a `use` or `require` are covered by this mechanism
too, since the inner require gets its own eval context. Plain string eval
optrees are still not retained.

Anonymous subs keep their prototype CVs in the pad of the CV enclosing them, so
the require-tree walk also walks the husk CV's pad (with `pad_cvs`, shared with
`B::GV::find_cv`, `add_cvs` and the `BEGIN`/`CHECK`/`INIT`/`END` block walk) and
covers each CV it finds there. The walk is recursive, finding anonymous subs
nested inside other anonymous subs at any depth, and keeps a seen hash because a
pad entry can refer back to its own CV.

A lexical sub (`my sub`) is different. Once its scope has exited, its pad value
slot no longer holds a usable CV, so the value walk cannot see it. Its live
prototype lives in the padname's `PROTOCV` instead, which `pad_cvs` reads from
the padname list. `PROTOCV` exists from 5.22, so on 5.20 a `my sub` at a
required file's top level runs but stays invisible and the file can wrongly
claim full subroutine coverage there.

A capture-free lexical sub shares one optree between its prototype and its
clones, so both carry the same start op. When a clone is reachable through a
value slot too (a `my method` called from an ordinary method, say), the sub
would otherwise be recorded twice, once from the value slot and once from
`PROTOCV`. `check_files` keeps only the first CV seen for each start op, so it
is recorded once.

A sub that itself encloses a lexical sub compiles with an `introcv`/`clonecv`
prologue before its first statement, one `clonecv` per enclosed `my sub` and a
`methstart` before them for a class method. In execution order that prologue
displaces the nextstate op `check_file` looks for, and in tree order it sits in
a nested lineseq wrapping the real first statement rather than that statement's
nextstate, which is what `sub_info` expects. So `check_file` steps past the
prologue ops to the first `COP`, and `sub_info` steps past a leading `methstart`
and then a nested prologue lineseq (identified by its own leading
`introcv`/`clonecv`, so ordinary nested blocks are left alone) to reach the
first statement. Without this the enclosing sub is dropped from the report with
any lexical sub reachable only through it, and the file can wrongly claim full
subroutine coverage. This gap is not specific to required files. The enclosing
sub is covered from 5.20, while each enclosed `my sub` still needs `PROTOCV` and
so stays invisible before 5.22.

An anonymous sub defined inside a `BEGIN`/`CHECK`/`INIT`/`END` block lives only
in that block's own pad, not in the enclosing file's pad, so `special_block_cvs`
gathers those block CVs and their pads are walked too. Without this such an anon
runs but appears in no report and the file can wrongly claim full subroutine
coverage.

Option A remains the supported long-term path. Once a released perl can keep
require optrees itself, the leaveeval hook can be dropped for those perls.

## Statement counts for partially executed files

Keeping the optree solves the mapping problem but note one further detail.
Statement counts are recorded at run time keyed by op address, so once the tree
survives to `END`, counts and structure line up and partially executed top-level
code (for example a module with `return if $loaded` style guards or conditional
definitions) reports true covered and uncovered lines, which is exactly the
missing data. Op-address reuse, which today can match a stale count from a freed
module tree against a later op at the same address, also becomes less likely
because the trees are no longer freed mid-run.

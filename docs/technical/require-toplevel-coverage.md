# Missing Coverage for Top-Level Module Statements

When a module is loaded with `require` or `use`, Devel::Cover collects no
coverage at all for the statements, branches and conditions in the module's
top-level code (the code outside any subroutine). The lines are not reported as
uncovered. They are simply absent from the coverage structure, which inflates
the reported percentages. A module whose subs are fully exercised reports 100%
statement coverage even if half its top-level code never ran.

The tests `t/internal/module_top_level.t` and `tests/module_top_level`
demonstrate the problem. The golden results for `module_top_level` show
`Module_top_level.pm` at 100% with every top-level line blank. The same
deficiency has been baked into the golden results of `module1` and friends for
years (lines 10 and 11 of `Module1.pm`).

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
the refcount semantics of `op_free`, and on the husk CV's pad remaining valid,
none of which are documented guarantees. It also misses requires that die part
way through, where `pp_leaveeval` never runs, though those trees are freed
during the die unwinding anyway, so nothing can be done about them without core
support.

String evals that perform a `use` or `require` are covered by this mechanism
too, since the inner require gets its own eval context. Plain string eval
optrees are still not retained, and anonymous subs defined at file scope are
still uncovered - their prototype CVs live in the husk CV's pad, which would
need a pad walk of the retained CVs (the remaining part of GH #51).

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

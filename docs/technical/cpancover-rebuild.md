# cpancover rebuild mode

Rebuild mode regenerates every already-covered distribution on
cpancover.com with the current Devel::Cover and the current default
report, in batches, interleaved with ordinary new-release processing.
It replaces the ad hoc "run a script, rebuild everything, hope nothing
breaks" approach that was used for previous report-format migrations.

## Entry point

```sh
dc cpancover-run-loop-rebuild
```

The recipe runs indefinitely. It is intended to be started manually
(e.g. inside the controller container) when a new Devel::Cover release
or new default report requires the existing results to be regenerated.

### Tunables

- `CPANCOVER_REBUILD_BATCH` - how many distdirs to rebuild per iteration
  (default `100`). Set lower for a more responsive site during the
  rebuild; higher for faster completion on a quiet server.
- `CPANCOVER_TIMEOUT` - per-module docker timeout. Inherited from the
  normal loop; no rebuild-specific override.

## State on disk

All state lives under `$results_dir`:

- `<distdir>/` - coverage results for a distribution. Presence of
  `cover.json` marks the distdir as covered.
- `__failed__/<distdir>` - timestamp file marking a distribution that
  failed to build. Left in place across rebuild cycles so the site
  still shows "last known" results.
- `__rebuilt__/<distdir>` - timestamp file marking a distribution that
  has been processed this rebuild cycle. Cleared wholesale at the end
  of a cycle. This directory does not exist outside rebuild mode.
- `.cpancover_status` - `key=value` file written by `bin/cpancover` at
  the end of each pass. Read by the recipe to decide whether to
  regenerate HTML and whether the cycle has finished.

The rebuild queue is the union of `<distdir>` (where `cover.json`
exists) and the entries in `__failed__/`, minus anything already in
`__rebuilt__/`. Entries are taken oldest-first by the mtime of
`cover.json` (or `__failed__/<distdir>` for failures that never
produced coverage data), so heavily stale results are regenerated
first.

Defunct distributions (those that `cpanm --info` can no longer
resolve) are purged from the queue rather than fed to a doomed
rebuild: the distdir, its `__failed__/` marker, and any
`__rebuilt__/` marker are all removed.

## Lifecycle

One invocation of `cpancover-run-loop-rebuild` proceeds through three
phases.

### 1. Initial HTML regeneration

The recipe calls `cpancover --generate_html` once at startup. This
picks up any manual changes to the site's static assets and guarantees
the index matches the on-disk results before the rebuild begins.

### 2. Rebuild loop

Each iteration runs two passes and reads the status file between them:

1. **Normal pass** -
   `cpancover_latest | cpancover --build --rebuild --rebuild_batch 0`.
   Process anything new that has appeared on CPAN since the last cycle.
   `--rebuild` is on so every touched distdir gets flagged as rebuilt,
   but `--rebuild_batch 0` skips the dedicated rebuild pass. If
   `new_count > 0` after this pass, regenerate HTML.
2. **Rebuild pass** -
   `cpancover --nobuild --rebuild --rebuild_batch $batch`. Pull the
   next batch of oldest unrebuilt distdirs, resolve each back to a
   CPAN release path via `cpanm --info`, and feed them to
   `cover_modules`. If `rebuilt_count > 0`, regenerate HTML.

The loop exits as soon as the status file reports `all_rebuilt=1`,
which happens the first time `Collection::all_rebuilt` finds every
entry in `known_distdirs` flagged.

### 3. Fall through

At the end of the rebuild cycle the recipe:

- `rm -rf` the `__rebuilt__/` directory, clearing every marker so the
  next rebuild cycle starts from a clean slate.
- Calls `cpancover_run_loop`, the ordinary perpetual-build loop. The
  site continues operating normally until the next rebuild is
  triggered.

## Interaction with existing machinery

- **compress_old_versions** runs inside `cpancover_generate_html`, as
  in the normal loop. Rebuilt distdirs replace the previous contents
  at the same path, so version compression still kicks in when the
  new version supersedes enough old versions.
- **Log retention**: every rebuild run produces a fresh
  `<log_name>.out.gz` in `$results_dir`. Failed rebuilds refresh the
  existing `<distdir>/.log_ref` to point at the new log, so users
  clicking "log" on a failing distribution see the most recent
  failure rather than a stale one from months ago. Old `.out.gz`
  files accumulate until the normal log-retention policy reaps them.
- **`is_covered` / `is_failed` semantics change in rebuild mode**: a
  distdir counts as "done" only if it has both been processed and
  flagged rebuilt this cycle. Outside rebuild mode the methods
  behave as before.

## Failure handling

A distribution that fails during a rebuild pass is flagged rebuilt
anyway so the cycle does not retry it on the next iteration. The
existing results dir is left in place so the site does not develop a
hole. `.log_ref` is rewritten to point at the fresh failure log, and
the `__failed__/<distdir>` marker is written so subsequent ordinary
runs know not to waste time on it. The next time a user triggers
`cpancover-run-loop-rebuild`, the failed entry will be retried from
scratch.

## Re-triggering

Because the recipe clears `__rebuilt__/` at the end of a cycle, a
subsequent invocation of `dc cpancover-run-loop-rebuild` starts a
fresh cycle over the entire site. There is no auto-detection of stale
Devel::Cover versions; rebuild cycles are explicit operator actions.

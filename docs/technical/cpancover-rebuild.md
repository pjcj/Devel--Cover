# cpancover rebuild mode

Rebuild mode regenerates every already-covered distribution on cpancover.com
with the current Devel::Cover and the current default report, in batches,
interleaved with ordinary new-release processing. It replaces the ad hoc "run a
script, rebuild everything, hope nothing breaks" approach that was used for
previous report-format migrations.

## Entry point

```sh
dc cpancover-run-loop-rebuild
```

The recipe runs indefinitely. Start it manually (e.g. inside the controller
container) when a new Devel::Cover release or new default report requires the
existing results to be regenerated.

### Tunables

- `CPANCOVER_REBUILD_BATCH` - how many distdirs to rebuild per iteration
  (default `100`). Set lower for a more responsive site during the rebuild;
  higher for faster completion on a quiet server.
- `CPANCOVER_TIMEOUT` - per-module docker timeout. Inherited from the normal
  loop; no rebuild-specific override.
- `CPANCOVER_LATEST_INDEX` - the release index file, in the
  `CPAN::Releases::Latest` cache format, that the recipes read instead of the
  `CPAN::Releases::Latest` cache file. `cpancover --latest` fetches the full
  release list into the cache file once a day, and between those fetches it
  merges in the releases uploaded since a day before it last printed the full
  list. The mtime of a marker file, the cache file name followed by `.full`,
  records the last time `cpancover --latest` printed the full list. The other
  recipes fetch the full list when the mtime of the cache file is more than a
  day old, and leave the marker alone. The recipes only read a file this
  variable names, so a test can run them offline. Unset in normal use.

## State on disk

All state is under `$results_dir`:

- `<distdir>/` - coverage results for a distribution. Presence of `cover.json`
  (the summary feed produced by the `json_summary` reporter) marks the distdir
  as covered.
- `__failed__/<distdir>` - timestamp file marking a distribution that failed to
  build. Left in place across rebuild cycles so the site still shows "last
  known" results. A report with a marker is stale, so the next build that
  produces a report replaces it, in any mode.
- `__rebuilt__/<distdir>` - timestamp file marking a distribution that has been
  processed this rebuild cycle. Cleared wholesale at the end of a cycle. This
  directory does not exist outside rebuild mode.
- `.cpancover_status` - `key=value` file written by `bin/cpancover` at the end
  of each pass. Read by the recipe to decide whether to regenerate HTML and
  whether the cycle has finished.

The rebuild queue is the union of `<distdir>` (where `cover.json` exists) and
the entries in `__failed__/`, minus anything already in `__rebuilt__/`. Entries
are taken oldest-first by the mtime of `cover.json` (or `__failed__/<distdir>`
for failures that never produced coverage data), so heavily stale results are
regenerated first.

Each candidate is resolved to the current release of its distribution through
the `CPAN::Releases::Latest` index before it is built. A candidate that is still
current is rebuilt as it is. A superseded candidate is marked rebuilt and its
current release is built in its place, so no container starts for a release path
CPAN no longer serves. A distribution CPAN no longer lists is marked rebuilt and
otherwise left alone, report and markers included.

## Lifecycle

One invocation of `cpancover-run-loop-rebuild` proceeds through three phases.

### 1. Initial HTML regeneration

The recipe calls `cpancover --generate_html` once at startup. This picks up any
manual changes to the site's static assets and guarantees the index matches the
on-disk results before the rebuild begins.

### 2. Rebuild loop

Each iteration runs two passes and reads the status file between them:

1. **Normal pass** -
   `cpancover_latest | cpancover --build --rebuild --rebuild_batch 0`. Process
   anything new that has appeared on CPAN since the last cycle. `--rebuild` is
   on so every touched distdir gets flagged as rebuilt, but `--rebuild_batch 0`
   skips the dedicated rebuild pass. If `new_count > 0` after this pass,
   regenerate HTML.
2. **Rebuild pass** - `cpancover --nobuild --rebuild --rebuild_batch $batch`.
   Pull the next batch of oldest unrebuilt distdirs, resolve each to the current
   release of its distribution through the release index, and feed those to
   `cover_modules`. If `rebuilt_count > 0`, regenerate HTML.

The loop exits as soon as the status file reports `all_rebuilt=1`, which happens
the first time `Collection::all_rebuilt` finds every entry in `known_distdirs`
flagged.

### 3. Fall through

At the end of the rebuild cycle the recipe:

- Removes the `__rebuilt__/` directory with `rm -rf`, clearing every marker so
  the next rebuild cycle starts with none.
- Calls `cpancover_run_loop`, the ordinary perpetual-build loop. The site
  continues operating normally until the next rebuild is triggered.

## Interaction with existing machinery

- **compress_old_versions** runs inside `cpancover_generate_html`, as in the
  normal loop. Rebuilt distdirs replace the previous contents at the same path,
  so version compression still runs when the new version supersedes enough old
  versions.
- **Log retention**: every rebuild run produces a fresh `<log_name>.out` in
  `$results_dir`, compressed to `.out.gz` only when `CPANCOVER_COMPRESS` is set.
  Failed rebuilds refresh the existing `<distdir>/.log_ref` to point at the new
  log, so users clicking "log" on a failing distribution see the most recent
  failure rather than a stale one from months ago. Old log files accumulate
  until the normal log-retention policy deletes them.
- **`is_covered` / `is_failed` semantics change in rebuild mode**: a distdir
  counts as "done" only if it has both been processed and flagged rebuilt this
  cycle. Outside rebuild mode the methods behave as before.

## Failure handling

A distribution that fails during a rebuild pass is flagged rebuilt anyway so the
cycle does not retry it on the next iteration. A rebuild has failed when it
leaves no `cover.json` written since the build began, whether the container
produced nothing or timed out. The existing results dir is left in place so the
site still has a report for it. `.log_ref` is rewritten to point at the fresh
failure log, and the `__failed__/<distdir>` marker is written so later ordinary
runs skip it. The next time a user triggers `cpancover-run-loop-rebuild`, the
failed entry will be retried from scratch.

## Re-triggering

Because the recipe clears `__rebuilt__/` at the end of a cycle, the next
`dc cpancover-run-loop-rebuild` starts a fresh cycle over the entire site.
Nothing detects stale Devel::Cover versions. An operator starts each rebuild
cycle.

## Running on cpancover.com

This is the production deploy sequence. It assumes `/cover/dc` is a checkout of
the branch you want to deploy and that you have shell access on the
cpancover.com host. Everything runs on cpancover.com itself. The image is built
locally and pushed to Docker Hub from the same host.

### 1. Build and push the new Docker image

```sh
cd /cover/dc
dc docker-build -e prod
```

This builds `pjcj/cpancover:<timestamp>-<sha>` and `pjcj/cpancover:latest`, tags
both locally, and pushes both to Docker Hub.

### 2. Stop the running controller

```sh
dc cpancover-docker-kill
dc cpancover-docker-rm
```

### 3. Verify with a small batch

```sh
CPANCOVER_REBUILD_BATCH=5 dc cpancover-controller-rebuild-batch
```

This runs exactly one rebuild pass and the post-batch HTML regeneration, then
exits. Inspect the site and `/cover/staging/.cpancover_status`:

```sh
cat /cover/staging/.cpancover_status
# new_count=0
# rebuilt_count=5
# all_rebuilt=0
```

Repeat with the same batch size until you're confident nothing is going wrong.

### 4. Start the full rebuild loop

```sh
dc cpancover-controller-run-rebuild
```

This runs for a long time. It reads `CPANCOVER_REBUILD_BATCH` once at startup
(default 100), then runs batches until `all_rebuilt=1`, at which point it clears
`__rebuilt__/` and falls through to the perpetual `cpancover-run-loop`.

### 5. If something goes wrong mid-rebuild

```sh
dc cpancover-docker-kill # stop the controller and any module containers
dc cpancover-docker-rm   # clean up
```

`__rebuilt__/` markers are preserved, so the next
`dc cpancover-controller-run-rebuild` resumes where the previous run stopped. No
distdir is rebuilt twice in the same cycle.

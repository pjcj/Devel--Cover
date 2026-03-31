# Partial Self-Coverage

Devel::Cover cannot instrument its own modules using standard `cover` because
they are loaded during bootstrap before instrumentation activates. The only
existing mechanism is `DEVEL_COVER_SELF`, which enables a specialised two-pass
XS tracing mode covering all DC modules.

However, many DC modules - report generators, annotation handlers, HTML support,
path utilities - are loaded on demand, well after bootstrap. These can be
instrumented normally using `-select` to override the default ignore pattern.

## How It Works

Devel::Cover normally blocks its own modules via two mechanisms:

1. **Ignore pattern** - a default `-ignore` of `/Devel/Cover[./]` added in
   `Devel::Cover.pm` during `BEGIN`.
2. **Hard-coded filter** - `_want_cover_for()` rejects any file matching
   `Devel/Cover` when `$Self_cover_run` is false.

The `-select` option already overrides mechanism 1 (select takes priority over
ignore in `use_file()`). The partial self-coverage change relaxes mechanism 2:
if `-select` patterns are active and a DC module matches one of them,
`_want_cover_for()` lets it through.

The `bin/cover` guard (which normally hard-exits if Devel::Cover is loaded) is
also relaxed when `-select` is active, allowing report generation under
instrumentation.

## Module Classification

### Bootstrap Modules (Not Coverable)

Loaded via compile-time `use` chains from `Devel::Cover.pm`. Their ops are
compiled before instrumentation activates:

- `Devel::Cover` (main + XS)
- `Devel::Cover::Core`
- `Devel::Cover::DB`
- `Devel::Cover::DB::Digests`
- `Devel::Cover::DB::File`
- `Devel::Cover::DB::IO`
- `Devel::Cover::Criterion` and all subclasses (Statement, Branch, Condition
  variants, Subroutine, Time, Pod)
- `Devel::Cover::Dumper`
- `Devel::Cover::Inc`

Only `DEVEL_COVER_SELF` (full two-pass XS tracing) can cover these.

### Late-Loaded Modules (Coverable)

Loaded at runtime via `require` or `eval "use"`. These are compiled after
instrumentation is active:

**Library modules** (tested by `t/internal/`):

- `Devel::Cover::DB::Structure` - abstract structure of source files
- `Devel::Cover::Path` - path shortening for reports
- `Devel::Cover::Static` - static analysis of uncovered files

**Report modules** (exercised by running `bin/cover`):

- All `Devel::Cover::Report::*` modules
- `Devel::Cover::Html_Common`
- `Devel::Cover::Web`
- `Devel::Cover::Truth_Table`
- `Devel::Cover::Base::Editor`
- `Devel::Cover::Annotation::*`

**Other late-loaded modules:**

- `Devel::Cover::Op`
- `Devel::Cover::DB::IO::JSON`, `DB::IO::Storable`, `DB::IO::Sereal`,
  `DB::IO::Base`
- `Devel::Cover::Collection` (cpancover only)
- `Devel::Cover::Test` (test harness)

## Running Self-Coverage

### Recipes

The `utils/dc` script provides three recipes:

```bash
# Cover library modules via their dedicated tests
dc dc-cover-lib

# Cover report modules by running bin/cover under instrumentation
dc dc-cover-reports

# Run both and merge into a combined report
dc dc-cover
```

Equivalent Makefile targets: `make dc_cover_lib`, `make dc_cover_reports`,
`make dc_cover`.

### How dc-cover-lib Works

Runs `t/internal/path.t` and `t/internal/static.t` under `-MDevel::Cover` with
`-select` matching only the modules under test. Only Path.pm and Static.pm
appear in the coverage report.

### How dc-cover-reports Works

1. Generates a rich input `cover_db` by running several e2e tests under normal
   Devel::Cover (no self-coverage). This DB contains varied coverage patterns -
   partial branches, uncovered conditions, multiple criteria - to exercise the
   report code paths thoroughly.
2. Runs `bin/cover` under `-MDevel::Cover` with `-select` for report and support
   modules, pointed at the rich input DB. This instruments the report modules as
   they process the coverage data.

### Manual Usage

To cover a specific module:

```bash
perl -Iblib/lib -Iblib/arch \
  -MDevel::Cover=-select,Devel/Cover/Path,-db,my_db,-merge,0 \
  t/internal/path.t

perl -Iblib/lib -Iblib/arch bin/cover my_db -report html_crisp
```

## Adding Coverage for New Modules

When adding a new late-loaded module or writing tests for an existing one:

1. Write the test in `t/internal/`.
2. Add the module to the `-select` pattern and the test to the run list in
   `dc_cover_lib` in `utils/dc`.
3. Run `dc dc-cover-lib` to verify coverage appears.
4. If the module is loaded during bootstrap via a `use` chain, check whether
   that `use` can be converted to a runtime `require` (as was done for `Path.pm`
   in `DB.pm`).

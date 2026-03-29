# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

Devel::Cover is a Perl code coverage analysis tool that provides statement,
branch, condition, subroutine, and pod coverage metrics. The module replaces
Perl ops with functions that count execution to determine code coverage. It
includes various reporting formats including HTML, text, and vim integration.

## Build and Test Commands

This project uses ExtUtils::MakeMaker for building and testing:

### Basic Build Process

```bash
perl Makefile.PL
make
make test
make install
```

### Test Commands

```bash
# Run all tests in parallel (preferred)
make t

# Run all tests sequentially
make test

# Run a single test (runs with coverage, saves output to <test>.out)
make out TEST=empty_else

# Run all tests on all Perl versions
make all_test

# Generate HTML report for a single test
make html TEST=empty_else

# Compare test output with golden file
make diff TEST=empty_else
```

### Generating Golden Results

Golden results are the expected test output files stored in
`test_output/cover/`.

```bash
# Generate golden results for a single test, current Perl version
make gold TEST=empty_else

# Generate golden results for a single test, ALL Perl versions
make all_gold TEST=empty_else
```

### Coverage Analysis

```bash
# Basic coverage for uninstalled module
cover -test

# Manual coverage collection
cover -delete
HARNESS_PERL_SWITCHES=-MDevel::Cover make test
cover

# Coverage for a specific program
perl -MDevel::Cover yourprog.pl args
cover
```

### Development Commands

```bash
# Generate ctags
make tags

# Show version
make show_version

# Create test files from tests/ directory
# (automatically done by Makefile.PL)

# Self-coverage analysis (full, using DEVEL_COVER_SELF)
make self_cover

# Partial self-coverage (late-loaded modules only)
make dc_cover          # combined report
make dc_cover_lib      # library modules (Path, Static)
make dc_cover_reports  # report modules via bin/cover

# Create distribution
make dist
```

## Code Quality Tools

### Linting and Formatting

- **perlcritic**: Configured via `.perlcriticrc` (severity 2, allows unsafe)
- **perltidy**: Configured via `.perltidyrc` (2-space indentation, specific
  formatting rules)
- Run both tools on all modified files before committing

### Testing Requirements

- Tests must use Test:More system (not Test2 as it is not core)
- All new code requires tests in the `t/` directory
- Tests should be run with `yath` test runner
- Coverage verification using Devel::Cover with JSON reports

## Architecture Overview

### Core Modules

Modules loaded at bootstrap (before instrumentation activates) cannot be
covered without `DEVEL_COVER_SELF`. Late-loaded modules (reports, Path,
Static, etc.) can be covered using `-select` - see
`docs/technical/self-coverage.md`.

**Coverage Collection**:

- `Devel::Cover` - Main module that hooks into Perl's op execution
- `Devel::Cover::Core` - Bootstrap utility (remove_contained_paths)
- `Devel::Cover::Op` - Handles operation coverage tracking
- `Devel::Cover::DB` - Database storage and management
- `Devel::Cover::Inc` - Include path management (auto-generated)

**Coverage Criteria**:

- `Devel::Cover::Statement` - Statement coverage
- `Devel::Cover::Branch` - Branch coverage
- `Devel::Cover::Condition*` - Condition coverage (multiple variants)
- `Devel::Cover::Subroutine` - Subroutine coverage
- `Devel::Cover::Pod` - POD documentation coverage

**Storage Backends** (`Devel::Cover::DB::IO::*`):

- `Storable` - Binary format (core module)
- `JSON` - JSON format (preferred if available)
- `Sereal` - Sereal format (fastest if available)

**Reporting System** (`Devel::Cover::Report::*`):

- `Html*` - Multiple HTML report variants (basic, minimal, subtle)
- `Text*` - Text-based reports
- `Vim` - Vim editor integration
- `Json` - JSON output format
- `Compilation` - Compilation error format

### Binary Tools

- `cover` - Main coverage report generator
- `cpancover` - CPAN coverage analysis tool
- `gcov2perl` - Convert gcov files to Devel::Cover format

### Test Infrastructure

**Directory Structure**:

- `tests/` - Source test files
- `t/e2e/` - Generated end-to-end tests (created by `perl Makefile.PL`)
- `t/internal/` - Internal module tests
- `test_output/cover/` - Golden results (expected output) for different Perl
  versions

**Test File Generation**:

When `perl Makefile.PL` runs, it generates test files in `t/e2e/`:

- `tests/foo` (no extension) → `t/e2e/afoo.t` (prefixed with 'a')
- `tests/bar.t` → `t/e2e/bar.t` (copied directly, no prefix)

**Golden Results**:

- Files are named `<test>.<perl_version>` (e.g., `empty_else.5.042000`)
- Not every Perl version needs its own golden file. The test system finds the
  closest matching version that is less than or equal to the current Perl
  version. For example, if golden files exist for `5.020000` and `5.038000`, a
  test run on 5.28.0 uses `5.020000` and a run on 5.40.0 uses `5.038000`.
- Only generate a new golden file when a Perl version produces genuinely
  different coverage output (e.g. due to optree changes or new ops). If the
  output matches an earlier version's golden file, no new file is needed.
- `$Latest_t` in `Makefile.PL` defines the latest tested Perl version

### Perl Version Management (plenv)

This project uses `plenv` to manage multiple Perl versions for testing. The
`.perl-version` file sets the default version to `dc-dev`.

**Available Versions**:

- `dc-<version>` - Non-threaded builds (e.g., `dc-5.38.0`)
- `dc-<version>-thr` - Threaded builds (e.g., `dc-5.38.0-thr`)
- `dc-dev` - Development version (usually the latest stable version)

**Common plenv Commands**:

```bash
# List all available Perl versions
plenv versions

# Show current version
plenv version

# Temporarily switch version for current shell
plenv shell dc-5.38.0

# Run a command with a specific version
PLENV_VERSION=dc-5.38.0 make out TEST=empty_else
```

**Multi-Version Testing**:

```bash
# Run all tests on all configured Perl versions
make all_test

# Generate golden results for all versions
make all_gold TEST=empty_else

# Run arbitrary command on all versions
dc all-versions <command>
```

**Adding a New Perl Version**:

See `docs/perl-version-update.md` for the full step-by-step guide.

## Documentation

The `docs/` directory contains project documentation including contribution
guidelines, release procedures, and a Perl version update guide. The
`docs/technical/` subdirectory contains detailed technical documentation on
coverage internals such as branch/condition handling, class coverage, and optree
adjustments.

## Development Notes

### Style Guidelines

- Use British English throughout the project (e.g., "optimised" not "optimized",
  "colour" not "color", "behaviour" not "behavior")

### Perl Preamble

All files using `5.20.0` must use this standard preamble:

```perl
use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );
```

- `use 5.20.0` implies `use strict`, so do not add it explicitly
- Use `use 5.x.y;` (without the `v` prefix) throughout the project
- Additional features (e.g. `say`) may be included where needed

### Code Generation

- `lib/Devel/Cover/Inc.pm` is auto-generated by `Makefile.PL`
- Test files in `t/e2e/` are auto-generated from `tests/` directory
- The build process customises tests for the current Perl version

### XS Component

- Contains C code (`Cover.xs`, `Cover.c`) for low-level Perl integration
- Uses typemap in `utils/typemap`

### Version Compatibility

- Supports Perl 5.20+
- Has version-specific test outputs for different Perl versions
- Self-adjusts for different Perl installations

### Docker Support

- Multiple Docker configurations in `docker/` directory
- Support for different Perl versions and development environments

### Creating New Files

- When creating new files, use the current year only in the copyright header
- Example: `# Copyright 2026, Paul Johnson (paul@pjcj.net)`
- Do not copy date ranges from existing files (e.g., avoid `2004-2025`)

### Git Workflow

**Branch Naming**:

- Use `GH-<issue>-<description>` format for branches (e.g., `GH-362-optree-if`)

**Pull Requests**:

- When creating a PR, always reference the associated issue using
  `Fixes #<issue>` or `Closes #<issue>` in the PR body
- This ensures the issue is automatically closed when the PR is merged
- Example PR body:

```markdown
Fixes #362

## Summary
- Brief description of changes

## Test plan
- [ ] Tests pass
```

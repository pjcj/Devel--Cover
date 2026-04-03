# Profiling XS Runtime Overhead

This document explains how to profile the C-level runtime overhead of
Devel::Cover's XS code. The techniques here measure where time is
spent *during test execution* (the instrumented op dispatch loop), not
the END-time Perl processing (DB writes, deparsing, report generation).

## Prerequisites

- macOS (for the `sample` command; see [Other Platforms](#other-platforms)
  for Linux alternatives)
- A non-trivial benchmark workload (the Gedcom test suite works well)
- Devel::NYTProf (optional, for Perl-level END-time profiling)

## Build with debug symbols

The `sample` tool needs DWARF symbols to map instruction addresses back
to C function names. Build Cover.bundle with `-g`:

```bash
make OPTIMIZE="-O2 -g"
```

This keeps optimisation on (so the profile reflects real performance)
while adding the symbol tables needed for profiling.

## Choose a benchmark

The Gedcom genealogy library provides a good workload - it exercises
many ops across a realistic codebase. The benchmark lives in
`tmp/runs/Gedcom-1.22/` and uses the `royal.ged` data file.

```bash
cd tmp/runs/Gedcom-1.22
```

### Baseline timing

Measure without coverage first:

```bash
time perl -Mblib -e '
  use Gedcom;
  for my $i (1..20) {
    my $ged = Gedcom->new("royal.ged");
    $ged->validate;
    $ged->resolve_xrefs;
  }
'
```

Then with coverage:

```bash
DC="-Mblib=$HOME/g/perl/Devel--Cover"
time perl $DC -MDevel::Cover=-silent,1,-db,/tmp/dc_bench_db -Mblib -e '
  use Gedcom;
  for my $i (1..20) {
    my $ged = Gedcom->new("royal.ged");
    $ged->validate;
    $ged->resolve_xrefs;
  }
'
```

The difference is the total overhead. In March 2026 this was 0.12s vs
0.92s (before optimisation) and 0.12s vs 0.52s (after hotspot #1).

## Sampling with macOS `sample`

Run the benchmark in the background and attach `sample` to it:

```bash
DC="-Mblib=$HOME/g/perl/Devel--Cover"
perl $DC -MDevel::Cover=-silent,1,-db,/tmp/dc_bench_db -Mblib -e '
  use Gedcom;
  for my $i (1..20) {
    my $ged = Gedcom->new("royal.ged");
    $ged->validate;
    $ged->resolve_xrefs;
  }
' > /dev/null 2>/dev/null &
PID=$!
sleep 0.3
sample "$PID" 5 -file /tmp/dc_sample.txt
wait "$PID"
```

Key points:

- `sleep 0.3` gives the process time to start before sampling begins
- `sample "$PID" 5` samples for 5 seconds at 1ms intervals
- `-file /tmp/dc_sample.txt` saves the output for analysis
- The 20-iteration loop ensures the process runs long enough for
  sampling to capture runtime behaviour rather than just startup/shutdown

### Timing the sleep

If the process finishes before `sample` attaches, increase the
iteration count. If `sample` captures mostly END-time processing,
increase iterations or reduce the sample duration. The goal is to
capture the `Perl_runops_standard` loop, not the cleanup phase.

## Analysing the sample output

The `sample` tool produces a hierarchical call tree. Each line shows a
sample count and a function name:

```text
+     ! 513 dc_nextstate  (in Cover.bundle) + 240
        +     ! : 498 cover_time  (in Cover.bundle) + 92
        +     ! : | 245 cover_time.cold.1  (in Cover.bundle) + 48
```

Child entries are *subsets* of their parent, not additions. In this
example, 498 of the 513 `dc_nextstate` samples went into `cover_time`,
and 245 of those 498 went into the cold path at offset +48.

### Aggregation script

To get a flat breakdown of all Cover.bundle functions, extracting
leaf-only samples (self-time, excluding time spent in callees):

```bash
perl -0777 -ne '
  my @all = split /\n/;
  my (%leaf, %inclusive);
  for my $i (0 .. $#all) {
    next unless $all[$i] =~
      /(\d+)\s+([\w.]+)\s+\(in Cover\.bundle\)/;
    my ($count, $func) = ($1, $2);
    $func =~ s/\.cold\.\d+//;        # merge cold paths
    $inclusive{$func} += $count;

    # Leaf test: next meaningful line has equal or less depth
    my $cur_depth = () = $all[$i] =~ /\|/g;
    my $is_leaf   = 1;
    for my $j ($i + 1 .. $#all) {
      next if $all[$j] =~ /^\s*$/;
      last unless $all[$j] =~ /\d+\s+\S+/;
      my $next_depth = () = $all[$j] =~ /\|/g;
      $is_leaf = 0 if $next_depth > $cur_depth;
      last;
    }
    $leaf{$func} += $count if $is_leaf;
  }

  my $total = 0;
  $total += $_ for values %leaf;
  print "Leaf (self-time) samples in Cover.bundle: $total\n\n";
  for (sort { $leaf{$b} <=> $leaf{$a} } keys %leaf) {
    printf "%6d  %5.1f%%  %s\n",
      $leaf{$_}, 100 * $leaf{$_} / $total, $_;
    last if $leaf{$_} < 3;
  }
' /tmp/dc_sample.txt
```

### Reading the call tree directly

For understanding call chains, grep for specific functions:

```bash
# Show the dc_nextstate call tree
grep -A 30 'dc_nextstate.*Cover.bundle' /tmp/dc_sample.txt

# Show all top-level dc_* op handlers
grep -E '^\s+\+\s+!\s+\d+\s+dc_' /tmp/dc_sample.txt

# Count cover_ function mentions
grep -c 'cover_' /tmp/dc_sample.txt
```

The hierarchical view is essential for understanding *where within a
function* the time is spent - the `+ offset` value on each line
corresponds to an instruction offset, and the child entries show which
callees dominate.

## Perl-level profiling with NYTProf

For profiling the END-time Perl code (DB writes, deparsing, report
generation), use Devel::NYTProf:

```bash
cd tmp/runs/Gedcom-1.22
DC="-Mblib=$HOME/g/perl/Devel--Cover"
perl $DC -MDevel::Cover=-silent,1,-db,/tmp/dc_bench_db \
  -d:NYTProf -Mblib -e '
  use Gedcom;
  my $ged = Gedcom->new("royal.ged");
  $ged->validate;
  $ged->resolve_xrefs;
'
nytprofhtml
```

NYTProf cannot see inside XS/C functions, so it is only useful for
Perl-side costs. For the XS runtime, use `sample` as described above.

## Interpreting results

### Architecture of the XS runtime

The XS code replaces Perl's op dispatch functions with instrumented
versions:

| Original op  | Replacement  | What it covers        |
| ------------ | ------------ | --------------------- |
| pp_nextstate | dc_nextstate | statement + time      |
| pp_and       | dc_and       | branch/condition      |
| pp_or        | dc_or        | branch/condition      |
| pp_dor       | dc_dor       | branch/condition      |
| pp_cond_expr | dc_cond_expr | branch/condition      |
| pp_entersub  | dc_entersub  | subroutine            |
| pp_padrange  | dc_padrange  | statement (multi-pad) |

Each replacement op follows the same pattern:

1. `check_if_collecting` - is this file being covered?
2. If yes, call the appropriate `cover_*` function
3. Call the original op via the saved function pointer

### What to look for

The main cost centres in the XS runtime are:

- **get_key / fnv1a_hash_file_line** - computing the unique key for
  each op (hashes the filename bytes and line number)
- **cover_time** - gettimeofday + hash lookup + arithmetic (only when
  time coverage is enabled)
- **cover_statement** - hash lookup + counter increment
- **cover_logop / get_conditional_array / add_conditional** - condition
  tracking with hash lookups
- **check_if_collecting** - strcmp/strncmp filename matching
- **Perl_hv_common / SipHash** - Perl's hash implementation, called
  from all the above via hv_fetch with KEY_SZ-byte keys

When optimising, focus on the functions with the highest *self-time*
(leaf samples). Inclusive counts tell you where time flows, but
self-time tells you where the CPU is actually stalled.

## Other platforms

### Linux

Use `perf` instead of `sample`:

```bash
# Record
perf record -g -p "$PID" -- sleep 5

# Report (flat profile)
perf report --no-children --sort=dso,symbol

# Report (call tree)
perf report --children --sort=dso,symbol
```

The analysis approach is the same - look for Cover.so functions with
high self-time.

### Instruments (macOS)

Xcode's Instruments app provides a GUI alternative to `sample` with
flame graphs and timeline views. Use the "Time Profiler" instrument,
attach to the running benchmark process, and filter by the Cover.bundle
module.

## Example profile (March 2026, post-hotspot #1)

After eliminating snprintf from get_key() and deduplicating get_key()
calls per statement, the profile showed:

| Area                     | % of DC overhead | Dominant cost         |
| ------------------------ | ---------------- | --------------------- |
| cover_time               | 37%              | gettimeofday, SipHash |
| dc_nextstate self        | 18%              | fnv1a_hash_file_line  |
| cover_logop / conditions | 17%              | get_conditional_array |
| check_if_collecting      | 10%              | strcmp, strncmp       |
| cover_statement          | 10%              | hv_fetch, sv_setiv    |
| op handler overhead      | 7%               | dc_and, dc_or self    |

Total overhead at this point: ~0.40s on the Gedcom benchmark (down from
0.80s before hotspot #1).

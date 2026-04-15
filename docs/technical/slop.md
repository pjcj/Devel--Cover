# SLOP: Scaled Likelihood Of Problems

SLOP is Devel::Cover's risk-scoring metric. It combines cyclomatic complexity
and code coverage into a single number that answers: "where should I spend my
testing effort?" This document records the research, the decisions, and the
design.

## Motivation

Coverage percentages tell you how much of a file is tested, but not how
dangerous the untested parts are. A file at 80% coverage could be low risk (the
missing 20% is simple, linear code) or high risk (the missing 20% contains
deeply nested logic with many branches). A single metric combining complexity
and coverage answers: "which files most need attention?"

## Literature Review

### McCabe's Cyclomatic Complexity (1976)

Thomas McCabe's seminal paper ["A Complexity Measure"][mccabe] (IEEE TSE,
SE-2(4), pp. 308-320) defines cyclomatic complexity as a property of the control
flow graph:

```text
v(G) = e - n + 2p
```

where e = edges, n = nodes, p = connected components. For a single subroutine (p
= 1) this simplifies to `e - n + 2`.

### [NIST SP 500-235][nist]: Structured Testing (Watson & McCabe, 1996)

The authoritative practical guide. Provides the counting rule that most tools
implement:

> "If all decisions are binary and there are p binary decision predicates, v(G)
> = p + 1."

Section 4.1 (p. 25) explicitly addresses short-circuit operators:

> "Boolean operators add either one or nothing to complexity, depending on
> whether they have short-circuit evaluation semantics that can lead to
> conditional execution of side-effects."

In Perl, `&&`, `||`, `//`, `and`, `or` all use short-circuit evaluation, so each
adds +1 to CC. The NIST document also covers loops (each loop condition is a
decision point with two outgoing edges) and ternary operators (equivalent to
if-else).

### [The CRAP Metric][crap] (Savoia & Evans, 2007)

CRAP (Change Risk Anti-Patterns) is the only published, widely adopted formula
that combines complexity and coverage into a risk score:

```text
CRAP(m) = CC(m)^2 * (1 - cov(m)/100)^3 + CC(m)
```

The formula is multiplicative: complex code with low coverage is far riskier
than either factor alone. The exponents make it non-linear - a method with CC=10
and 0% coverage scores 110 (10^2 + 10), whilst at 100% coverage it scores just
10\.

The CRAP threshold of 30 is the accepted "unacceptable" boundary. At CC=10, you
need at least 42% coverage to stay below it. At CC=25, you need 80%.

### Other Relevant Research

- **Malaiya & Denton (1999)** -
  ["Estimating Defect Density Using Test Coverage"][malaiya]. Log-Poisson model
  showing coverage predicts residual defects.
- **Elbaum et al. (2002)** - ["Test Case Prioritization"][elbaum] (IEEE TSE).
  APFD metric for coverage-based prioritisation.
- **Nagappan & Ball (2005)** - ["Relative Code Churn"][nagappan] (ICSE). Churn
  predicts defects at 89% accuracy. This informed the decision to not pursue
  VCS-integration approaches (option 7 below) - powerful but unavailable when
  running coverage on a CPAN distribution, which has no VCS history.
- **Felderer & Schieferdecker (2014)** -
  ["Taxonomy of Risk-Based Testing"][felderer]. Classification of risk-based
  approaches in testing.

## Survey of Other Coverage Tools

An investigation of 10 coverage tools across different ecosystems found almost
none compute a composite risk score:

| Tool               | Risk score?   | Approach                      |
| ------------------ | ------------- | ----------------------------- |
| Istanbul/nyc (JS)  | No            | Raw percentages only          |
| JaCoCo (Java)      | No            | CRAP requested 2014, declined |
| Coverage.py        | No            | `--sort=miss` by missed count |
| gcov/lcov          | No            | `--missed --sort` by count    |
| SimpleCov (Ruby)   | No            | Percentages only              |
| **PHPUnit**        | **Yes: CRAP** | Per-method CRAP score         |
| **NDepend (.NET)** | **Yes: CRAP** | Per-method CRAP + PageRank    |
| SonarQube          | Indirect      | Tech debt ratio, coverage sep |
| Codecov/Coveralls  | No            | Manual "critical file" labels |
| **OtterWise**      | **Yes: CRAP** | Per-method CRAP score         |

The only published, widely adopted coverage-based risk formula is CRAP. Most
tools report raw numbers and let users sort by percentage or missed count.
PHPUnit and NDepend are the two most prominent implementations.

## Options Considered

Seven approaches were evaluated before settling on CRAP + SLOP:

### Option 1: Missed count

`risk = missed_statements + missed_branches + missed_conditions`. What lcov's
`--sort=miss` does. Simple, size-weighted, and directly answers "where would
adding tests have the most impact?" - but has no published backing as a risk
metric, and does not capture the interaction between complexity and coverage.

### Option 2: Weighted missed count

Like option 1 but with configurable weights per criterion (e.g.
`W_s=1, W_b=2, W_c=2, W_u=1`). Acknowledges that branch gaps are more
consequential than statement misses, but the default weights are an opinion with
no empirical basis, and adding user-configurable knobs is undesirable.

### Option 3: CRAP (chosen)

The standard formula from Savoia & Evans. Well-studied, widely adopted, captures
the key insight that complex + untested = risky. Non-linear: punishes the
combination more than either factor alone. Cyclomatic complexity, which CRAP
requires, is computed during the optree walk.

### Option 4: CRAP-lite

Approximates CC as `total_branch_points + 1`, avoiding the need for real CC
computation. Rejected because genuine CC turned out to be straightforward to
compute during the existing walk, and the approximation misses `foreach` loops
and `while`/`until`/`for` loops (whose branch points are suppressed by
Devel::Cover's leaveloop guard).

### Option 5: Normalised coverage gap

A weighted average of uncovered fractions per criterion, ranging from 0 to
sum(weights). Size-blind: a 5-line file at 0% scores the same as a 5000-line
file at 0%. If the goal is "where to spend effort", size matters.

### Option 6: Geometric mean of uncovered fractions

`risk = (u_stmt * u_branch * u_cond * u_sub) ^ (1/4)`. Naturally penalises
weakness on any single criterion, but if any criterion is 100% covered the
entire product becomes 0 regardless of the others. Size-blind, no published
backing.

### Option 7: Change-frequency weighted

`risk = commits_in_last_N_months * (1 - coverage / 100)`. Based on Nagappan &
Ball (ICSE 2005) - empirically the strongest predictor of actual defects.
However, it requires VCS history, which is unavailable when running coverage on
a CPAN distribution and is a significant new feature beyond a formula change.

### Comparison

| Option          | Available? | Size-aware? | Published? | Complexity |
| --------------- | ---------- | ----------- | ---------- | ---------- |
| 1 Missed count  | Yes        | Yes         | No\*       | Trivial    |
| 2 Weighted miss | Yes        | Yes         | No         | Low        |
| 3 CRAP          | Yes        | Yes         | Yes        | Medium     |
| 4 CRAP-lite     | Yes        | Yes         | Approx     | Medium     |
| 5 Normalised    | Yes        | No          | No         | Low        |
| 6 Geometric     | Yes        | No          | No         | Low        |
| 7 Churn-based   | No (VCS)   | Yes         | Yes        | High       |

\* lcov uses missed count for sorting but does not call it "risk".

## Why CRAP, and Why SLOP

CRAP was the clear winner: it is the only published, peer-reviewed, widely
adopted coverage-based risk formula. It required cyclomatic complexity, which
Devel::Cover did not previously compute, but the existing optree walk provided a
natural place to count decision points with minimal new code.

However, CRAP has a usability problem: its range is enormous. A simple method
with CC=1 at 100% coverage scores 1. A complex method with CC=50 at 0% coverage
scores 2,550. Even moderate codebases can produce scores in the tens or even
hundreds of thousands. This makes it difficult to scan a table and quickly
assess relative risk.

SLOP compresses this range using a natural logarithm:

```text
slop = crap > 1 ? ln(crap) * 10 : 0
```

This maps the CRAP range of approximately 1-20,000 to roughly 0-100. Each +10
SLOP represents approximately 2.7x worse CRAP (one e-fold). The standard CRAP
threshold of 30 maps to SLOP ~34.

The name "Scaled Likelihood Of Problems" was chosen to:

- Describe what it measures (likelihood of problems, scaled for readability)
- Be memorable and slightly irreverent (like CRAP itself)
- Distinguish it from raw CRAP in reports and documentation

### Display strategy

SLOP is the primary displayed value in all reports. Raw CRAP remains accessible
in Html_crisp tooltips for users who want the standard metric. This gives the
best of both worlds: a scannable, bounded number in the table, with the
published metric one hover away.

## Architectural Placement

Risk scoring is computed in `DB::calculate_summary` (via `summarise_complexity`)
rather than in individual reporters. This means all reporters and CLI tools get
SLOP data for free without duplicating the formula. The DB layer gains an
opinion about what "risk" means, but the alternative - each reporter computing
its own risk - leads to duplication and divergence. A shared utility module was
considered but adds indirection for no practical benefit when there is exactly
one formula.

## Computing Cyclomatic Complexity

### NIST counting rules for Perl

The NIST SP 500-235 counting rules, applied to Perl constructs:

| Construct             | CC  | Reason (per NIST)            |
| --------------------- | --- | ---------------------------- |
| `if`                  | +1  | 2 outgoing edges             |
| `elsif`               | +1  | additional decision          |
| `else`                | 0   | not a new decision           |
| `unless`              | +1  | equivalent to `if`           |
| `while` / `until`     | +1  | loop condition               |
| `for` (C-style)       | +1  | condition check              |
| `foreach` / `for-in`  | +1  | implicit "more items?" check |
| `do {} while/until`   | +1  | bottom-test condition        |
| short-circuit logical | +1  | `&&` `and` `or` `//` etc.    |
| short-circuit assign  | +1  | `&&=` `//=` etc.             |
| `? :` (ternary)       | +1  | equivalent to if-else        |
| `xor`                 | +1  | decision node                |
| `try`/`catch`         | 0   | not a source decision        |

Note that `else` does **not** contribute. The `if` already has two outgoing
edges; the else is simply one of those edges.

`foreach` counts because at the CFG level there is a decision node with two
outgoing edges: "more elements - enter body" vs "exhausted - exit loop". This is
structurally identical to a `while` loop. McCabe's 1976 paper and NIST SP
500-235 do not mention `foreach` by name (the construct did not exist in the
languages of the era), but the graph-theoretic definition is unambiguous.

### CC in other Perl tools

Two CPAN modules compute CC. Both describe themselves as approximations, and
each makes different trade-offs against the NIST definition.

**Perl::Critic::Utils::McCabe** counts keywords (`if`, `else`, `elsif`,
`unless`, `until`, `while`, `for`, `foreach`) and operators (`&&`, `||`, `?`,
`and`, `or`, `xor`, `&&=`, `||=`, `<<=`, `>>=`). Differences from NIST: it
includes `else` (not a decision per NIST - the `if` already has two edges) and
the bit-shift assigns `<<=`/`>>=`, but omits `//` and `//=`.

**Perl::Metrics::Simple** uses a broader token set including comparison
operators (`eq`, `==`, `cmp`, etc.), flow control (`next`, `last`, `goto`), list
ops (`grep`, `map`), and negation (`!`, `not`, `!~`). This captures a wider
notion of "complexity" than the strict CFG-based NIST definition; the additional
tokens are not decision points in the control flow graph but may reflect
cognitive complexity.

For example, given this subroutine:

```perl
sub config {
    my $host = shift // "localhost";  # short-circuit
    my $port = shift // 8080;         # short-circuit
    if ($port > 1024) {               # two edges
        return "$host:$port";
    } else {                          # not a new decision
        die "privileged port";
    }
}
```

| Tool                  | CC  | Counts                       |
| --------------------- | --- | ---------------------------- |
| NIST definition       | 4   | 2x // + if + base            |
| Perl::Critic          | 3   | if + else + base (misses //) |
| Perl::Metrics::Simple | 6   | if + else + 2x // + >        |
| Devel::Cover          | 4   | 2x // + if + base            |

Perl::Critic under-counts because `//` is not in its operator set, and
over-counts because it includes `else`. Here the two errors partially cancel.
Perl::Metrics::Simple counts the `>` comparison, which is not a control flow
decision.

Each tool serves a different purpose. Perl::Critic's approximation works well
for its policy checks. Perl::Metrics::Simple's broader count reflects
readability concerns. For CRAP scoring, the strict NIST definition is the right
choice because the formula's exponents amplify any inflation in the CC value.

### Counting during the optree walk

Devel::Cover already walks the Perl optree for every subroutine during coverage
collection. The XS walker (`dc_walk_ops_r` in Cover.xs) fires callbacks for op
types that map directly to CC decision points. The CC counter in
`_get_cover_walk` (lib/Devel/Cover.pm) simply increments a `$decisions` counter
for each decision-type callback:

| Callback type | Perl constructs                  | CC  |
| ------------- | -------------------------------- | --- |
| `cond_expr`   | if/elsif/ternary                 | +1  |
| `logop`       | `&&` `and` `or` `//` while/until | +1  |
| `logassignop` | `&&=` `//=` etc.                 | +1  |
| `xor`         | xor/^^                           | +1  |
| `iter`        | foreach loops (XS callback)      | +1  |
| `argdefelem`  | signature defaults (5.26+/5.43+) | +1  |

CC = `$decisions + 1` (the "+1" is the base path through the subroutine).

The `iter` and `argdefelem` callbacks required XS changes; see "Loop conditions
and the OP_ITER distinction" below for details.

Signature defaults (`OP_ARGDEFELEM` on 5.26+, `OP_PARAMTEST` on 5.43+) are
counted because each default is a conditional: "was an argument supplied? if
not, use the default". This creates a decision point in the control flow graph.

### Loop conditions and the OP_ITER distinction

The XS walker (Cover.xs) originally suppressed the callback for logops whose
first child is `OP_ITER`:

```c
if (cLOGOPx(op)->op_first->op_type != OP_ITER)
    dc_walk_callback(aTHX_ op, callback, "logop", cv);
```

This meant `foreach` loops were invisible to the CC counter. A new `"iter"`
callback type was added to count them.

Block-form `while`, `until`, and C-style `for` loops compile to logops whose
first child is the condition expression (not `OP_ITER`). These pass through the
XS walker and fire `"logop"` callbacks. However, the Perl-level `_walk_logop`
discards them when the parent is a `leaveloop` op (to avoid double-counting with
branch coverage). The CC counter in `_get_cover_walk` increments `$decisions`
before `_walk_logop` is called, so these loops are correctly included in CC even
though they may not generate branch coverage entries.

Summary of loop construct handling:

| Construct              | CC? | Branch? | Notes           |
| ---------------------- | --- | ------- | --------------- |
| `while (COND) {}`      | Yes | No      | leaveloop guard |
| `until (COND) {}`      | Yes | No      | leaveloop guard |
| `for (INIT;COND;INCR)` | Yes | No      | leaveloop guard |
| `foreach my $x (@l)`   | Yes | No      | iter callback   |
| `do {} while (COND)`   | Yes | Yes     | parent=leave    |
| `EXPR while COND`      | Yes | Yes     | parent=leave    |
| `while (1) {}`         | No  | N/A     | constant-folded |

### Per-subroutine vs per-file granularity

CC is computed per-subroutine rather than per-file. Per-sub granularity costs
little extra (the walk already processes one CV at a time) and enables proper
per-method CRAP scoring as PHPUnit does, plus per-sub detail in the subroutine
coverage section.

## The Formulae

### CRAP

```text
CRAP(m) = CC(m)^2 * (1 - cov(m)/100)^3 + CC(m)
```

Where:

- CC(m) is the cyclomatic complexity of subroutine m
- cov(m) is the combined statement+branch+condition coverage percentage

At 100% coverage, CRAP equals CC (complexity alone). At 0% coverage, CRAP equals
CC^2 + CC. The cubic exponent on the coverage gap makes the penalty steep: going
from 90% to 80% coverage hurts much more than going from 50% to 40%.

### SLOP

```text
slop = crap > 1 ? ln(crap) * 10 : 0
```

The minimum possible CRAP score is 1 (a subroutine with CC=1 at 100% coverage:
1^2 * 0^3 + 1 = 1). Since ln(1) = 0, SLOP is zero for a perfect score. The `> 1`
guard makes this explicit and avoids any floating-point edge cases near the
boundary. The factor of 10 scales the range to roughly 0-100.

### Coverage for CRAP

The original CRAP paper specifies basis path coverage - exercising a basis set
of linearly independent paths through the control flow graph. In practice, no
major implementation uses this. PHPUnit and GMetrics use line coverage; NDepend
uses branch/statement coverage. CPAN distributions have no basis path coverage
tool available.

Devel::Cover uses combined statement, branch, and condition coverage for lines
within the subroutine's start and end lines:

```perl
for my $name (qw( statement branch condition )) {
    # sum $covered and $total across lines $start..$end
}
$total ? 100 * $covered / $total : 100
```

This is stronger than line coverage alone (the most common substitute) but
weaker than full basis path coverage. A subroutine with no coverable points
(e.g. a constant) gets 100%.

## Colour Thresholds

The `slop_class` function maps SLOP values to the existing c0-c3 CSS classes
used throughout Devel::Cover for coverage colouring. The thresholds are
log-transforms of established CRAP boundaries:

| SLOP range | CSS class | CRAP equivalent | Meaning        |
| ---------- | --------- | --------------- | -------------- |
| < 16       | c3        | < 5             | Low risk       |
| 16-34      | c2        | 5-30            | Moderate risk  |
| 34-41      | c1        | 30-60           | High risk      |
| >= 41      | c0        | >= 60           | Very high risk |

The CRAP threshold of 30 (the accepted "unacceptable" boundary) maps to SLOP
~34, sitting at the c2/c1 boundary.

## Aggregation Levels

CRAP is defined per-subroutine, but developers need risk scores at multiple
levels. The aggregation strategy:

### Per-subroutine

The CRAP formula applied directly. This is the canonical level.

### Per-file

File CC is computed as `sum(sub CCs) - count + 1`. The subtraction avoids
double-counting the base paths: if a file has three subroutines with CC 3, 5,
and 2, the file CC is `(3+5+2) - 3 + 1 = 8` rather than `10`. File coverage is
the combined statement+branch+condition coverage from the summary. File CRAP and
SLOP follow from these.

### Per-directory

Same approach as per-file but aggregating across all files in the directory.

### Module-level (Total)

Treats the entire codebase as one body. Module CC is
`sum(all sub CCs) - total count + 1`. Module coverage is the combined coverage
from the Total summary. This is useful as a progress tracker: the same codebase
measured over time, so the size sensitivity is a feature. Improving coverage or
reducing complexity both lower the score.

## Report Display

### Text report

CC and SLOP columns appear in the subroutine detail section, showing per-sub
values alongside the subroutine name and line number.

### Html_crisp report

- **Index page**: SLOP column in the file table, sortable. Tooltips show a
  frosted-glass popup with the top SLOP subroutines and their raw CRAP scores.
- **Top SLOP section**: Highlights the highest-SLOP files with inline pills.
- **Module badge**: A neutral stat-badge in the header showing the module-level
  SLOP score.
- **Directory rows**: Directory total rows include SLOP with tooltips.
- **File pages**: Per-line SLOP detail in the subroutine section.

## Key Files

| File                                   | Role                             |
| -------------------------------------- | -------------------------------- |
| `lib/Devel/Cover.pm`                   | CC counting in `_get_cover_walk` |
| `Cover.xs`                             | XS walker callbacks              |
| `lib/Devel/Cover/DB.pm`                | CRAP/SLOP formulae, aggregation  |
| `lib/Devel/Cover/DB/Structure.pm`      | CC and end-line storage          |
| `lib/Devel/Cover/Report/Text.pm`       | Text report CC/SLOP columns      |
| `lib/Devel/Cover/Report/Html_crisp.pm` | HTML report, tooltips            |
| `lib/Devel/Cover/Web.pm`               | Shared CSS and tooltip base      |
| `bin/cover`                            | Structure wiring in `manage_dbs` |

## References

1. T. J. McCabe, ["A Complexity Measure,"][mccabe] in *IEEE Transactions on
   Software Engineering*, vol. SE-2, no. 4, pp. 308-320, Dec. 1976.

2. A. H. Watson and T. J. McCabe,
   ["Structured Testing: A Testing Methodology Using the Cyclomatic Complexity Metric,"][nist]
   NIST Special Publication 500-235, Aug. 1996.

3. A. Savoia, ["Pardon My French, But This Code Is C.R.A.P.,"][crap] Artima
   Developer, Jul. 2007.

4. Y. K. Malaiya and J. Denton,
   ["Estimating Defect Density Using Test Coverage,"][malaiya] Technical Report
   CS-98-104, Colorado State University, 1999.

5. S. Elbaum, A. G. Malishevsky, and G. Rothermel,
   ["Test Case Prioritization: A Family of Empirical Studies,"][elbaum] in *IEEE
   Transactions on Software Engineering*, vol. 28, no. 2, pp. 159-182, Feb.
   2002\.

6. N. Nagappan and T. Ball,
   ["Use of Relative Code Churn Measures to Predict System Defect Density,"][nagappan]
   in *Proc. 27th International Conference on Software Engineering (ICSE)*, St.
   Louis, MO, May 2005, pp. 284-292.

7. M. Felderer and I. Schieferdecker,
   ["A Taxonomy of Risk-Based Testing,"][felderer] in *Int. J. Softw. Tools
   Technol. Transfer*, vol. 16, pp. 559-568, 2014.

[crap]: https://www.artima.com/weblogs/viewpost.jsp?thread=210575
[elbaum]: https://digitalcommons.unl.edu/cgi/viewcontent.cgi?article=1018&context=csearticles
[felderer]: https://arxiv.org/abs/1912.11519
[malaiya]: https://scispace.com/pdf/estimating-defect-density-using-test-coverage-5141799zod.pdf
[mccabe]: http://www.literateprogramming.com/mccabe.pdf
[nagappan]: https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/icse05churn.pdf
[nist]: https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication500-235.pdf

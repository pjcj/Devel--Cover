#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# Per-execution decision input vectors are recorded at runtime via XS and
# appear in the cover_db at $Run{decision_inputs}{$file}[$n]{$vector_key} =
# count.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is is_deeply ok subtest unlike )];

use Devel::Cover::DB             ();  ## no perlimports
use Devel::Cover::Mcdc           ();  ## no perlimports
use Devel::Cover::Test::Internal qw( run_under_cover write_script );

# A mock condition entry matching the structure Devel::Cover produces:
#   [0] hit counts per outcome
#   [1] {type, left, op, right}
#   [2] uncoverable markers per outcome.
sub mock_condition ($class, $hits, $info, $unc = undef) {
  bless [$hits, $info, $unc], "Devel::Cover::$class"
}

sub decision_inputs_for ($db, $file) {
  for my $run (values $db->{runs}->%*) {
    return $run->{decision_inputs}{$file} if $run->{decision_inputs}{$file};
  }
  return;
}

sub test_simple_and () {
  my $script = write_script("simple_and.pl", <<'PERL');
my @r;
sub two { my ($p, $q) = @_; push @r, $p && $q }
two(1, 1);
two(1, 0);
two(0, 1);
two(0, 0);
PERL

  my ($db, $path) = run_under_cover($script, "simple_and");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for simple_and";
  is @$di, 1, "one decision recorded";

  is_deeply $di->[0], { "1|1" => 1, "1|0" => 1, "0|X" => 2 },
    "vectors and counts: (1,1), (1,0), and two short-circuits to (0,X)";
}

# xor evaluates both operands, so the recorder sees the right operand on
# the stack at the logop and the decision result at the next op.  The
# vector must still record the actual (left, right) values.  The calls are
# asymmetric: with all four combinations the wrong mapping is a
# permutation of the right one and the test would pass regardless.
sub test_xor_vectors () {
  my $script = write_script("xor_vectors.pl", <<'PERL');
my @r;
sub either { my ($p, $q) = @_; push @r, ($p xor $q) }
either(1, 0);
either(1, 1);
PERL

  my ($db, $path) = run_under_cover($script, "xor_vectors");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for xor";

  my @recorded = grep defined, @$di;
  is @recorded, 1, "one decision recorded";
  is_deeply $recorded[0], { "1|0" => 1, "1|1" => 1 },
    "xor vectors record the operand values, not the result";
}

sub test_xor_compound_left () {
  my $script = write_script("xor_compound_left.pl", <<'PERL');
my @r;
sub f { my ($p, $q, $s) = @_; push @r, (($p && $q) xor $s) }
f(1, 1, 0);
f(1, 0, 1);
PERL

  my ($db, $path) = run_under_cover($script, "xor_compound_left");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for compound-left xor";

  my @recorded = grep defined, @$di;
  is @recorded, 1, "one root recorded (the xor)";
  is_deeply $recorded[0], { "1|1|0" => 1, "1|0|1" => 1 },
    "compound-left xor records the right operand, not the result";
}

sub test_xor_compound_right () {
  my $script = write_script("xor_compound_right.pl", <<'PERL');
my @r;
sub f { my ($p, $q, $s) = @_; push @r, ($p xor ($q && $s)) }
f(1, 1, 0);
f(0, 1, 1);
PERL

  my ($db, $path) = run_under_cover($script, "xor_compound_right");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for compound-right xor";

  my @recorded = grep defined, @$di;
  is @recorded, 1, "one root recorded (the xor)";
  is_deeply $recorded[0], { "1|1|0" => 1, "0|1|1" => 1 },
    "compound-right xor records the left operand, not the result";
}

sub test_worked_example () {
  my $script = write_script("worked.pl", <<'PERL');
my @r;
sub may_edit {
  my ($is_owner, $unlocked, $is_admin) = @_;
  push @r, ($is_owner && $unlocked) || $is_admin;
}
may_edit(1, 1, 1);
may_edit(1, 0, 1);
may_edit(0, 0, 1);
may_edit(0, 0, 0);
PERL

  my ($db, $path) = run_under_cover($script, "worked");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for worked example";

  # Find the entry recording the outer || root (3 columns; 4 distinct observed
  # vectors).  Inner && entries have no decision_inputs.
  my @recorded = grep defined, @$di;
  is @recorded, 1, "exactly one root recorded (outer ||)";

  is_deeply $recorded[0],
    { "1|1|X" => 1, "1|0|1" => 1, "0|X|1" => 1, "0|X|0" => 1 },
    "four distinct observed vectors, no phantom (1,0,0)";
}

sub test_coupled_decision_vectors () {
  my $script = write_script("coupled.pl", <<'PERL');
my @r;
sub coupled {
  my ($a, $b, $c) = @_;
  push @r, ($a && $b) || ($a && $c);
}
coupled(1, 1, 0);
coupled(1, 0, 1);
coupled(1, 0, 0);
coupled(0, 0, 0);
PERL

  my ($db, $path) = run_under_cover($script, "coupled");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for coupled decision";

  # One root, four columns ($a, $b, $a, $c)
  my @recorded = grep defined, @$di;
  is @recorded, 1, "exactly one root recorded (outer ||)";

  is_deeply $recorded[0],
    { "1|1|X|X" => 1, "1|0|1|1" => 1, "1|0|1|0" => 1, "0|X|0|X" => 1 },
    "coupled columns agree within every observed vector";
}

# On perls that do not fold a constant left operand (5.28-era), the recorder
# must still give it a column: the table always does, and a width disagreement
# surfaces as a short-vector warning at derivation time.
sub test_left_constant_width_parity () {
  my $script = write_script("left_const.pl", <<'PERL');
sub f { my ($b) = @_; my $r = (undef // $b) && 1; $r }
f(1);
f(0);
PERL

  my ($db, $path) = run_under_cover($script, "left_const");

  my $err = "";
  {
    open my $save, ">&", \*STDERR or die "Cannot dup STDERR: $!";
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">", \$err or die "Cannot redirect STDERR: $!";
    $db->cover;
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">&", $save or die "Cannot restore STDERR: $!";
  }

  unlike $err, qr|Ignoring short MC/DC vector|,
    "recorded vectors are as wide as the table";
}

sub test_repeated_observation () {
  my $script = write_script("repeated.pl", <<'PERL');
my @r;
sub two { my ($p, $q) = @_; push @r, $p && $q }
two(1, 1) for 1 .. 3;
two(0, 0) for 1 .. 5;
PERL

  my ($db, $path) = run_under_cover($script, "repeated");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for repeated";

  is_deeply $di->[0], { "1|1" => 3, "0|X" => 5 },
    "counts accumulate across executions";
}

sub test_no_inputs_without_mcdc () {
  my $script = write_script("no_mcdc.pl", <<'PERL');
my @r;
sub two { my ($p, $q) = @_; push @r, $p && $q }
two(1, 1);
two(1, 0);
two(0, 1);
two(0, 0);
PERL

  my ($db, $path) = run_under_cover(
    $script, "no_mcdc",
    criteria => [qw( statement branch condition subroutine )],
  );
  my $di = decision_inputs_for($db, $path);
  ok !$di, "decision_inputs absent when mcdc not selected";
}

# A compound decision whose value is discarded is rebuilt without observed
# vectors; synthesis must not then fabricate a false 100% MC/DC.
sub test_void_compound_no_false_coverage () {
  my $script = write_script("void_compound.pl", <<'PERL');
sub decision {
  my ($a, $b, $c, $d) = @_;
  ($a && $b) || ($c && $d);
  return;
}
decision(1, 1, 0, 0);
decision(0, 0, 0, 0);
decision(0, 0, 1, 1);
decision(1, 0, 1, 0);
PERL

  my ($db, $path) = run_under_cover($script, "void_compound");
  my $mcdc = $db->cover->file($path)->{mcdc};
  ok $mcdc, "mcdc derived for void compound decision";

  my ($decision) = grep $_->total >= 3, map @$_, values %$mcdc;
  ok $decision, "found the compound decision";
  is $decision->total,   4, "four atomics";
  is $decision->covered, 0, "synthesised compound claims no MC/DC coverage";
  ok $decision->error, "MC/DC error flagged, not a false 100%";
}

# The analyser derives its uncoverable set from the synthesised rows.  For an
# unproven table those rows are the evidence we distrust, so a column the
# analyser excused must not be silently excused in the derived MC/DC result;
# only explicit "# uncoverable mcdc" markers may excuse one there.
sub test_unproven_ignores_derived_uncoverable () {
  my $db = bless {}, "Devel::Cover::DB";

  # Worked example $a || ($b && $c): a compound decision, so unproven without
  # observed vectors.  The inner "# uncoverable condition" marker lets the
  # analyser excuse $c through the synthesised rows.
  my @conditions = (
    mock_condition(
      "Condition_and_3",
      [1, 0, 1],
      { type => "and_3", left => '$b', op => "&&", right => '$c' },
      [0, 1, 0],
    ),
    mock_condition(
      "Condition_or_3",
      [1, 1, 1],
      { type => "or_3", left => '$a', op => "||", right => '$b && $c' },
    ),
  );

  my $cover
    = { f1 => { condition => { 10 => \@conditions }, meta => { digest => "d" } }
    };
  $db->_derive_mcdc($cover);

  my $decision = bless $cover->{f1}{mcdc}{10}[0], "Devel::Cover::Mcdc";
  is $decision->covered, 0, "unproven table claims no MC/DC coverage";
  ok !$decision->uncoverable, "no atomic excused from an unproven table";
  is_deeply $decision->missing, ['$a', '$b', '$c'],
    "every atomic of an unproven table is reported missing";
}

# A file whose mcdc slot already exists must be skipped, leaving the existing
# entry untouched, while files without one are still derived.
sub test_derive_skips_existing_mcdc () {
  my $db = bless {}, "Devel::Cover::DB";

  my $conditions = sub { [
    mock_condition(
      "Condition_and_3",
      [1, 1, 1],
      { type => "and_3", left => '$a', op => "&&", right => '$b' },
    ),
  ] };
  my $existing = { 99 => "sentinel" };
  my $cover    = {
    done => {
      condition => { 10 => $conditions->() },
      mcdc      => $existing,
      meta      => { digest => "d1" },
    },
    fresh =>
      { condition => { 10 => $conditions->() }, meta => { digest => "d2" } },
  };
  $db->_derive_mcdc($cover);

  is $cover->{done}{mcdc}, $existing, "existing mcdc entry is left in place";
  is_deeply $cover->{done}{mcdc}, { 99 => "sentinel" },
    "existing mcdc content is untouched";
  ok $cover->{fresh}{mcdc}{10}, "file without mcdc is still derived";
}

# The recorder must record one accurate vector per completed evaluation and
# nothing for abandoned ones.  A die out of a decision abandons its frame; the
# next execution must not inherit the aborted execution's column values.
sub test_die_discards_abandoned_evaluation () {
  my $script = write_script("die_mid_decision.pl", <<'PERL');
sub f { die "boom" }
sub d { my ($a, $b) = @_; my $r = ($a && $b && f()) ? 1 : 0; $r }
eval { d(1, 1) };
d(0, 1);
PERL

  my ($db, $path) = run_under_cover($script, "die_mid_decision");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for die_mid_decision";

  my @recorded = grep defined, @$di;
  is @recorded, 1, "one decision recorded";
  is_deeply $recorded[0], { "0|X|X" => 1 },
    "aborted evaluation records nothing; completed one is not contaminated";
}

# Recursion through the same decision must record one vector per invocation, not
# merge the inner invocation into the outer's frame.
sub test_recursion_records_each_invocation () {
  my $script = write_script("recursive_decision.pl", <<'PERL');
sub r { my ($n) = @_; my $v = ($n <= 0) || r($n - 1); $v }
my $x = r(1);
PERL

  my ($db, $path) = run_under_cover($script, "recursive_decision");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for recursive_decision";

  my @recorded = grep defined, @$di;
  is @recorded, 1, "one decision recorded";
  is_deeply $recorded[0], { "0|1" => 1, "1|X" => 1 },
    "outer and inner invocations each record their own vector";
}

# A decision resolving while an abandoned inner frame is still on the stack must
# be counted once, and the abandoned frame must record nothing.
sub test_abandoned_inner_frame_not_double_counted () {
  my $script = write_script("abandoned_inner.pl", <<'PERL');
sub f { die "x" }
sub d { my ($a, $b) = @_; my $r = $a || eval { my $v = $b && f(); $v }; $r }
d(0, 1);
PERL

  my ($db, $path) = run_under_cover($script, "abandoned_inner");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for abandoned_inner";

  my @recorded = grep defined, @$di;
  is @recorded, 1, "only the completed outer decision is recorded";
  is_deeply $recorded[0], { "0|0" => 1 }, "outer vector counted exactly once";
}

# A decision ending a sort comparator resolves via the deferred path; each
# comparator invocation must record its own vector rather than blending values
# across invocations.  The ternary keeps the || classified as a condition rather
# than a statement-level branch.
sub test_sort_block_records_per_invocation () {
  my $script = write_script("sort_block.pl", <<'PERL');
my $numeric = 1;
sub srt {
  my @l = @_;
  my @s = sort { $numeric ? ($a <=> $b) || ($a cmp $b) : 0 } @l;
  @s
}
srt(1, 1);
srt(1, 1);
srt(2, 1);
PERL

  my ($db, $path) = run_under_cover($script, "sort_block");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for sort_block";

  my @recorded = grep defined, @$di;
  is @recorded, 1, "one decision recorded";
  is_deeply $recorded[0], { "0|0" => 2, "1|X" => 1 },
    "each comparator invocation records its own vector";
}

# A short-circuit deep in a chain resolves the whole decision in one jump.  The
# recorder must still snapshot the vector when the chain's operands are element
# accesses, whose optree roots are nulled ops, and when the cascade spans more
# than two logops.
sub test_chain_cascades_record_short_circuits () {
  my $script = write_script("chain_cascade.pl", <<'PERL');
sub h3 { my %h = @_; my $r = $h{a} || $h{b} || $h{c}; $r }
h3(a => 1, b => 0, c => 0);
h3(a => 0, b => 1, c => 0);
h3(a => 0, b => 0, c => 1);
h3(a => 0, b => 0, c => 0);
sub l4 { my ($a, $b, $c, $d) = @_; my $r = $a || $b || $c || $d; $r }
l4(1, 0, 0, 0);
sub a5 { my @v = @_; my $r = $v[0] || $v[1] || $v[2] || $v[3] || $v[4]; $r }
a5(1, 0, 0, 0, 0);
PERL

  my ($db, $path) = run_under_cover($script, "chain_cascade");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for chain_cascade";

  my %by_width;
  for my $d (grep defined, @$di) {
    my @cols = split /\|/, (keys %$d)[0];
    $by_width{ 0 + @cols } = $d;
  }

  is_deeply $by_width{3},
    { "1|X|X" => 1, "0|1|X" => 1, "0|0|1" => 1, "0|0|0" => 1 },
    "hash-element chain records a vector at every short-circuit depth";
  is_deeply $by_width{4}, { "1|X|X|X" => 1 },
    "lexical chain records a two-level cascaded short-circuit";
  is_deeply $by_width{5}, { "1|X|X|X|X" => 1 },
    "array-element chain records a three-level cascaded short-circuit";
}

# A decision wider than the analysis limit records no input vectors; a narrow
# decision alongside it is unaffected.
sub test_too_wide_decision_records_nothing () {
  my @vars   = map "\$v$_", 1 .. 17;
  my $args   = join ", ", ("1") x 17;
  my $script = write_script("too_wide.pl", <<PERL);
sub wide { my (@{[ join ", ", @vars ]}) = \@_; my \$r = @{[
  join " && ", @vars ]}; \$r }
wide($args);
sub two { my (\$p, \$q) = \@_; my \$r = \$p && \$q; \$r }
two(1, 0);
PERL

  my ($db, $path) = run_under_cover($script, "too_wide");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for too_wide";

  my @recorded = grep defined, @$di;
  is @recorded, 1, "only the narrow decision records vectors";
  is_deeply $recorded[0], { "1|0" => 1 },
    "the narrow decision's vector is unaffected";
}

# The condition of an if/unless statement is joined to its body by a void
# statement-level logop which condition coverage treats as a branch.  The
# chain itself is the decision and must record vectors under its own root.
sub test_unless_statement_chain () {
  my $script = write_script("unless_chain.pl", <<'PERL');
sub check { my ($p, $q, $r) = @_; return "no" unless $p && $q && $r; "yes" }
check(0, 0, 0);
check(1, 0, 0);
check(1, 1, 0);
check(1, 1, 1);
PERL

  my ($db, $path) = run_under_cover($script, "unless_chain");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for unless chain";

  my @recorded = grep defined, @$di;
  is @recorded, 1, "one decision recorded";
  is_deeply $recorded[0],
    { "0|X|X" => 1, "1|0|X" => 1, "1|1|0" => 1, "1|1|1" => 1 },
    "unless condition records full per-execution vectors";
}

sub test_if_statement_chain () {
  my $script = write_script("if_chain.pl", <<'PERL');
sub check { my ($p, $q, $r) = @_; if ($p && $q && $r) { return "yes" } "no" }
check(0, 0, 0);
check(1, 0, 0);
check(1, 1, 0);
check(1, 1, 1);
PERL

  my ($db, $path) = run_under_cover($script, "if_chain");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for if chain";

  my @recorded = grep defined, @$di;
  is @recorded, 1, "one decision recorded";
  is_deeply $recorded[0],
    { "0|X|X" => 1, "1|0|X" => 1, "1|1|0" => 1, "1|1|1" => 1 },
    "if condition records full per-execution vectors";
}

sub test_while_statement_chain () {
  my $script = write_script("while_chain.pl", <<'PERL');
sub drain { my ($p, $q) = @_; my $n = 3; while ($p && $q && $n) { $n-- } $n }
drain(1, 1);
drain(1, 0);
drain(0, 0);
PERL

  my ($db, $path) = run_under_cover($script, "while_chain");
  my $di = decision_inputs_for($db, $path);
  ok $di, "decision_inputs present for while chain";

  my @recorded = grep defined, @$di;
  is @recorded, 1, "one decision recorded";
  is_deeply $recorded[0],
    { "0|X|X" => 1, "1|0|X" => 1, "1|1|0" => 1, "1|1|1" => 3 },
    "while condition records a vector per loop test";
}

sub test_add_condition_cross_run_merge () {
  my $db = bless {}, "Devel::Cover::DB";
  my $cc = {};
  my $sc = [[42, { type => "or_3" }]];
  my $uc = { 42 => [[]] };

  $db->add_condition($cc, $sc, [[1, 0, 2]], $uc, [{ "1|1" => 1, "1|0" => 2 }]);
  $db->add_condition($cc, $sc, [[3, 4, 0]], $uc, [{ "1|1" => 5, "0|X" => 7 }]);

  is_deeply $cc->{42}[0][0], [4, 4, 2],
    "hit counts sum across runs (slots 0-2)";

  is_deeply $cc->{42}[0][3], { "1|1" => 6, "1|0" => 2, "0|X" => 7 },
    "observed-vector counts merged: shared key sums, new keys appended";
}

sub test_add_condition_xor_four_slot_merge () {
  my $db = bless {}, "Devel::Cover::DB";
  my $cc = {};
  my $sc = [[7, { type => "xor_4" }]];
  my $uc = { 7 => [[]] };

  $db->add_condition($cc, $sc, [[1, 2, 3, 4]], $uc);
  $db->add_condition($cc, $sc, [[5, 6, 7, 8]], $uc);

  is_deeply $cc->{7}[0][0], [6, 8, 10, 12],
    "xor four-slot hit counts (slots 0-3) sum across runs";
}

sub main () {
  subtest "simple two-leaf and"        => \&test_simple_and;
  subtest "xor vectors"                => \&test_xor_vectors;
  subtest "xor compound left"          => \&test_xor_compound_left;
  subtest "xor compound right"         => \&test_xor_compound_right;
  subtest "worked example"             => \&test_worked_example;
  subtest "coupled decision"           => \&test_coupled_decision_vectors;
  subtest "left constant width parity" => \&test_left_constant_width_parity;
  subtest "repeated observation"       => \&test_repeated_observation;
  subtest "no inputs without mcdc"     => \&test_no_inputs_without_mcdc;
  subtest "void compound no false coverage" =>
    \&test_void_compound_no_false_coverage;
  subtest "unproven ignores derived uncoverable" =>
    \&test_unproven_ignores_derived_uncoverable;
  subtest "derivation skips existing mcdc" => \&test_derive_skips_existing_mcdc;
  subtest "die discards abandoned evaluation" =>
    \&test_die_discards_abandoned_evaluation;
  subtest "recursion records each invocation" =>
    \&test_recursion_records_each_invocation;
  subtest "abandoned inner frame not double counted" =>
    \&test_abandoned_inner_frame_not_double_counted;
  subtest "sort block records per invocation" =>
    \&test_sort_block_records_per_invocation;
  subtest "chain cascades record short circuits" =>
    \&test_chain_cascades_record_short_circuits;
  subtest "too-wide decision records nothing" =>
    \&test_too_wide_decision_records_nothing;
  subtest "unless statement chain" => \&test_unless_statement_chain;
  subtest "if statement chain"     => \&test_if_statement_chain;
  subtest "while statement chain"  => \&test_while_statement_chain;
  subtest "cross-run merge"        => \&test_add_condition_cross_run_merge;
  subtest "xor four-slot merge"    => \&test_add_condition_xor_four_slot_merge;

  done_testing;
}

main;

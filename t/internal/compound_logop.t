#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# Under -coverage condition, a logop whose operands are themselves compound
# logops must record the outer joining operator.  Otherwise only the inner
# logops get condition tables, the joining operator has no representation, and
# an outer-operator fault (|| vs &&) is invisible to condition coverage.  These
# tests run on bare statement-level sub bodies (the context that triggers the
# drop) and assert which logops are recorded as conditions.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Cwd        qw( abs_path );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing is isnt ok )];

use Devel::Cover::DB ();

# Use a deterministic DB format so the test does not depend on which
# serialisation backend happens to be installed.  The child run inherits this
# via %ENV, so it writes the same format we read here.
BEGIN { $ENV{DEVEL_COVER_DB_FORMAT} = "JSON" }

my $Tmpdir = tempdir(CLEANUP => 1);

# Bare statement-level sub bodies (the context that triggers the drop), called
# in non-void context so the right operand's value is observed.
my $Source = <<'PERL';
my @r;
sub or_or     { my ($a, $b, $c, $d) = @_; ($a && $b) || ($c && $d) }  # OR_OR
sub and_and   { my ($a, $b, $c, $d) = @_; ($a && $b) && ($c && $d) }  # AND_AND
sub or_and    { my ($a, $b, $c, $d) = @_; ($a or $b) and ($c or $d) }  # OR_AND
sub left_only { my ($a, $b, $c) = @_; ($a && $b) || $c }  # LEFT_ONLY
sub or_flow   { my ($a, $b) = @_; ($a && $b) or return 0; 1 }  # OR_FLOW
sub dor_join  { my ($a, $b, $x) = @_; $x // ($a && $b) }  # DOR_JOIN
for my $v (
  [0, 0, 0, 0], [1, 0, 0, 0], [1, 1, 0, 0], [0, 1, 0, 0],
  [0, 0, 1, 0], [0, 0, 1, 1], [0, 1, 1, 1], [1, 1, 1, 1],
) {
  push @r, or_or(@$v);
  push @r, and_and(@$v);
  push @r, or_and(@$v);
  push @r, left_only(@$v);
  push @r, or_flow(@$v);
  push @r, dor_join(@$v);
}
PERL

# Shared state populated by _setup
my ($Cover,     $Path,    $Cond);
my ($Or_or,     $And_and, $Or_and);
my ($Left_only, $Or_flow, $Dor_join);

sub write_script ($name, $content) {
  my $path = File::Spec->catfile($Tmpdir, $name);
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
  $path
}

sub run_under_cover ($script, $label, @criteria) {
  my $cover_db   = File::Spec->catdir($Tmpdir, "cover_db_$label");
  my $abs_tmpdir = abs_path($Tmpdir);
  my $coverage   = @criteria ? "-coverage," . join(",", @criteria) . "," : "";
  my @cmd        = (
    $^X, "-Iblib/lib", "-Iblib/arch",
    "-MDevel::Cover=-db,$cover_db,-silent,1,${coverage}+select,$abs_tmpdir",
    $script,
  );
  system(@cmd) == 0 or die "Failed to run script under Devel::Cover: @cmd";

  my $db = Devel::Cover::DB->new(db => $cover_db);
  $db->merge_runs;
  # Devel::Cover resolves symlinks (e.g. /tmp -> /private/tmp on macOS)
  my $real_path = abs_path($script);
  ($db->cover, $real_path)
}

# Return { line => [ { type => ..., text => ... }, ... ] } for every recorded
# condition in the file.
sub conditions_for ($cover, $file) {
  my $f    = $cover->file($file)        or return {};
  my $cond = $f->criterion("condition") or return {};
  my %out;
  for my $line ($cond->items) {
    for my $c ($cond->location($line)->@*) {
      push $out{$line}->@*, { type => $c->type, text => $c->text };
    }
  }
  \%out
}

# Find the 1-based line number of the source line carrying $tag.
sub line_with ($content, $tag) {
  my @lines = split /\n/, $content;
  for my $i (0 .. $#lines) {
    return $i + 1 if $lines[$i] =~ /\Q$tag\E/;
  }
  die "tag $tag not found";
}

# Run the fixtures under -coverage condition and pull back the recorded
# condition tables for each tagged line.
sub _setup () {
  return if $Cover;
  my $prog = write_script("compound_logop.pl", $Source);
  ($Cover, $Path) = run_under_cover($prog, "compound_logop", "condition");
  $Cond = conditions_for($Cover, $Path);

  $Or_or   = $Cond->{ line_with($Source, "# OR_OR") }   // [];
  $And_and = $Cond->{ line_with($Source, "# AND_AND") } // [];
  $Or_and  = $Cond->{ line_with($Source, "# OR_AND") }  // [];

  $Left_only = $Cond->{ line_with($Source, "# LEFT_ONLY") } // [];
  $Or_flow   = $Cond->{ line_with($Source, "# OR_FLOW") }   // [];
  $Dor_join  = $Cond->{ line_with($Source, "# DOR_JOIN") }  // [];
}

# The outer || joining (a && b) and (c && d) must be recorded.
sub test_outer_or_recorded () {
  my @or = grep $_->{type} =~ /^or/, @$Or_or;
  ok @or, '($a && $b) || ($c && $d): outer || recorded as a condition'
    or diag "recorded: ", join " ; ", map "$_->{type}=$_->{text}", @$Or_or;
}

# The outer && joining (a or b) and (c or d) must be recorded.  Inner operands
# are 'or' here, so any 'and' condition on the line is the outer one.
sub test_outer_and_recorded () {
  my @and = grep $_->{type} =~ /^and/, @$Or_and;
  ok @and, '($a or $b) and ($c or $d): outer and recorded as a condition'
    or diag "recorded: ", join " ; ", map "$_->{type}=$_->{text}", @$Or_and;
}

# An outer && joining two compounds records exactly three tables: the two inner
# &&s plus the outer.
sub test_and_and_has_outer () {
  is @$And_and, 3,
    '($a && $b) && ($c && $d): outer && recorded alongside two inner &&s'
    or diag "recorded: ", join " ; ", map "$_->{type}=$_->{text}", @$And_and;
}

# A non-decision right operand keeps the outer logop a branch: ($a && $b) || $c
# has an atomic right operand, so only the inner && is a condition - the outer
# || must not be recorded.
sub test_left_compound_stays_branch () {
  my @or = grep $_->{type} =~ /^or/, @$Left_only;
  is @or, 0, '($a && $b) || $c: outer || stays a branch, not a condition'
    or diag "recorded: ", join " ; ", map "$_->{type}=$_->{text}", @$Left_only;
}

# A control-flow logop (... or return) is a branch, not a join, so its outer
# operator must not be promoted to a condition.
sub test_control_flow_stays_branch () {
  my @or = grep $_->{type} =~ /^or/, @$Or_flow;
  is @or, 0, '($a && $b) or return: outer or stays a branch, not a condition'
    or diag "recorded: ", join " ; ", map "$_->{type}=$_->{text}", @$Or_flow;
}

# A statement-level // joining a compound right operand is recorded (dor reuses
# the or condition machinery).
sub test_dor_join_recorded () {
  my @dor = grep $_->{type} =~ /^or/ && $_->{text} =~ m{//}, @$Dor_join;
  ok @dor, '$x // ($a && $b): outer // recorded as a condition'
    or diag "recorded: ", join " ; ", map "$_->{type}=$_->{text}", @$Dor_join;
}

sub types ($conds) { sort map $_->{type}, @$conds }

# The whole point: an outer-operator fault must be detectable.  || and &&
# joining the same two compounds must not produce identical condition tables.
sub test_fault_detectable () {
  isnt join("|", types($Or_or)), join("|", types($And_and)),
    "(a&&b)||(c&&d) and (a&&b)&&(c&&d) record distinct conditions";
}

sub main () {
  _setup;
  test_outer_or_recorded;
  test_outer_and_recorded;
  test_and_and_has_outer;
  test_fault_detectable;
  test_left_compound_stays_branch;
  test_control_flow_stays_branch;
  test_dor_join_recorded;
  done_testing;
}

main;

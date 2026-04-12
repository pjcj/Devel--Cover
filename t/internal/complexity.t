#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Cwd     ();
use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Digest::MD5 ();
use File::Spec  ();
use File::Temp  qw( tempdir );
use Test::More import => [qw( done_testing is ok )];

my $Root = Cwd::cwd();

use Devel::Cover::DB            ();
use Devel::Cover::DB::Structure ();

my $Tmpdir = tempdir(CLEANUP => 1);

sub md5_file ($path) {
  open my $fh, "<", $path or die "Cannot open $path: $!";
  binmode $fh;
  Digest::MD5->new->addfile($fh)->hexdigest
}

# Run a script under Devel::Cover and return ($db_path, $script_path).
sub run_cover ($label, $script_content) {
  my $script = File::Spec->catfile($Tmpdir, "$label.pl");
  my $db     = File::Spec->catdir($Tmpdir, "${label}_db");

  open my $fh, ">", $script or die "Cannot write $script: $!";
  print $fh $script_content;
  close $fh or die "Cannot close $script: $!";

  my @inc = map { "-I$_" } "$Root/blib/arch", "$Root/blib/lib", "$Root/lib";

  system($^X, @inc, "-MDevel::Cover=-db,$db,-silent,1", $script) == 0
    or die "Failed to run $label under Devel::Cover: $?";

  ($db, $script)
}

# Run a script under Devel::Cover and return the complexity hash for that
# script's file digest.
sub cover_complexity ($label, $script_content) {
  my ($db, $script) = run_cover($label, $script_content);

  my $st = Devel::Cover::DB::Structure->new(base => $db);
  $st->read_all;

  $st->get_complexity(md5_file($script))
}

# Line numbers matter - they are the hash keys for complexity lookup.
# If you change the layout, update the assertions below.
#
# Line 1: use strict;
# Line 2: use warnings;
# Line 3: (blank)
# Line 4: sub linear       - no decisions
# Line 5: sub one_if       - one cond_expr (if)
# Line 6: sub elsif_two    - two cond_exprs (if + elsif)
# Line 7: sub with_and     - one logop (&&)
# Line 8: sub ternary      - one cond_expr (?:)
# Line 9: sub with_foreach - one foreach loop (iter)

my $Cc = cover_complexity("cc_basic", <<'PERL');
use strict;
use warnings;

sub linear       { 42 }
sub one_if       { if ($_[0]) { return 1 } return 0 }
sub elsif_two    { if ($_[0] > 0) { 1 } elsif ($_[0] < 0) { -1 } else { 0 } }
sub with_and     { $_[0] && $_[1] }
sub ternary      { $_[0] ? 1 : 0 }
sub with_foreach { my $s; foreach my $x (@_) { $s .= $x } $s }

linear();
one_if(1);
elsif_two(1);
with_and(1, 1);
ternary(1);
with_foreach("a", "b");
PERL

ok defined $Cc, "complexity data present in structure";

is $Cc->{4}{linear}[0],       1, "linear: CC = 1";
is $Cc->{5}{one_if}[0],       2, "one if: CC = 2";
is $Cc->{6}{elsif_two}[0],    3, "if/elsif: CC = 3";
is $Cc->{7}{with_and}[0],     2, "&&: CC = 2";
is $Cc->{8}{ternary}[0],      2, "ternary: CC = 2";
is $Cc->{9}{with_foreach}[0], 2, "foreach: CC = 2";

# Summary aggregation tests
# Reuse the same test script layout (6 subs: CC = 1, 2, 3, 2, 2, 2).
{
  my ($db_path, $script) = run_cover("cc_summary", <<'PERL');
use strict;
use warnings;

sub linear       { 42 }
sub one_if       { if ($_[0]) { return 1 } return 0 }
sub elsif_two    { if ($_[0] > 0) { 1 } elsif ($_[0] < 0) { -1 } else { 0 } }
sub with_and     { $_[0] && $_[1] }
sub ternary      { $_[0] ? 1 : 0 }
sub with_foreach { my $s; foreach my $x (@_) { $s .= $x } $s }

linear();
one_if(1);
elsif_two(1);
with_and(1, 1);
ternary(1);
with_foreach("a", "b");
PERL

  my $st = Devel::Cover::DB::Structure->new(base => $db_path);
  $st->read_all;

  my $db = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  $db->set_structure($st);
  $db->calculate_summary(statement => 1, subroutine => 1);

  # Find the cover file key for our script
  my ($file) = grep /cc_summary\.pl$/, keys $db->{summary}->%*;
  ok defined $file, "summary contains cover file for test script";

  my $cs = $db->{summary}{$file}{complexity};
  ok defined $cs, "file summary has complexity entry";

  # 8 subs: 6 named + 2 BEGIN blocks from use strict/warnings.
  # CC values: 1,1 (BEGINs), 1,2,3,2,2,2 (named) = sum 14, mean 1.75
  is $cs->{max},   3,    "file complexity max = 3 (elsif_two)";
  is $cs->{mean},  1.75, "file complexity mean = 1.75";
  is $cs->{count}, 8,    "file complexity count = 8 subs";

  my $ts = $db->{summary}{Total}{complexity};
  ok defined $ts, "Total summary has complexity entry";

  is $ts->{max},   3,    "Total complexity max = 3";
  is $ts->{mean},  1.75, "Total complexity mean = 1.75";
  is $ts->{count}, 8,    "Total complexity count = 8";
}

done_testing;

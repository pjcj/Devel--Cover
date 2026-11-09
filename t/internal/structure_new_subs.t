#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Cwd        qw( getcwd );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing is is_deeply )];

use Devel::Cover::DB ();

my $Root     = getcwd;
my $Lib      = File::Spec->rel2abs("blib/lib");
my $Arch     = File::Spec->rel2abs("blib/arch");
my $Criteria = "statement,branch,subroutine";

sub write_file ($path, $content) {
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
}

sub run_prog ($dir, $criteria, $want_out, @args) {
  my @cmd = (
    $^X, "-I$Lib", "-I$Arch",
    "-MDevel::Cover=-db,cover_db,-silent,1,-coverage,$criteria",
    "prog.pl", @args,
  );
  local %ENV = %ENV;
  delete @ENV{qw( DEVEL_COVER_SELF DEVEL_COVER_OPTIONS )};
  chdir $dir or die "Cannot chdir $dir: $!";
  my $cmd    = join " ", map(qq("$_"), @cmd), "2>&1";
  my $out    = `$cmd`;
  my $status = $?;
  chdir $Root or die "Cannot chdir $Root: $!";
  is $status, 0, "prog.pl @args under $criteria exits 0" or diag $out;
  is $out, $want_out, "prog.pl @args under $criteria prints what it should";
}

sub counts ($dir, $name, $line) {
  chdir $dir or die "Cannot chdir $dir: $!";
  my $file
    = Devel::Cover::DB->new(db => "cover_db")->merge_runs->cover->file($name);
  chdir $Root or die "Cannot chdir $Root: $!";
  my $subs       = $file->subroutine->location($line) // [];
  my $statements = $file->statement->location($line)  // [];
  (
    [map $_->covered, grep $_->name eq "BEGIN", @$subs],
    [map $_->covered, @$statements],
  )
}

sub test_new_subs_on_other_lines () {
  my $dir = tempdir(CLEANUP => 1);
  write_file(File::Spec->catfile($dir, "prog.pl"), <<'PERL');
eval "use strict; 1" if $ARGV[0];
eval "use warnings; 1";
eval "use Carp; 1" if $ARGV[0];
PERL
  run_prog($dir, $Criteria, "");
  run_prog($dir, $Criteria, "", 1);
  my $want = { 1 => [1], 2 => [2], 3 => [1] };
  for my $line (sort keys %$want) {
    my ($begin) = counts($dir, "prog.pl", $line);
    is_deeply $begin, $want->{$line}, "other lines: BEGIN counts on line $line";
  }
}

sub write_loader ($dir) {
  my $lib = File::Spec->catdir($dir, "lib");
  mkdir $lib or die "Cannot mkdir $lib: $!";
  write_file(File::Spec->catfile($lib, "$_.pm"), "package $_;\n1;\n")
    for qw( ModA ModB ModC ModD );
  write_file(File::Spec->catfile($dir, "prog.pl"), <<'PERL');
use lib "lib";
my ($x, $y) = (1);
if ($x) { $y = 1 } else { $y = 2 }
sub load { for my $c (@_) { eval "use $c; 1" or die $@ } }
load(@ARGV);
PERL
}

sub test_repeated_line_two_runs () {
  my $dir = tempdir(CLEANUP => 1);
  write_loader($dir);
  run_prog($dir, $Criteria, "", "ModA");
  run_prog($dir, $Criteria, "", qw( ModA ModB ModC ));
  my ($begin) = counts($dir, "prog.pl", 4);
  my (undef, $statements) = counts($dir, "prog.pl", 3);
  is_deeply $begin,      [2, 1, 1], "two runs: BEGIN counts of the loader";
  is_deeply $statements, [2, 2, 0], "two runs: statement counts of the if";
}

sub test_repeated_line_three_runs () {
  my $dir = tempdir(CLEANUP => 1);
  write_loader($dir);
  run_prog($dir, $Criteria, "", "ModA");
  run_prog($dir, $Criteria, "", qw( ModA ModB ModC ));
  run_prog($dir, $Criteria, "", qw( ModA ModB ModC ModD ));
  my ($begin) = counts($dir, "prog.pl", 4);
  my (undef, $statements) = counts($dir, "prog.pl", 3);
  is_deeply $begin, [3, 2, 2, 1], "three runs: BEGIN counts of the loader";
  is_deeply $statements, [3, 3, 0], "three runs: statement counts of the if";
}

sub test_repeated_line_four_runs () {
  my $dir = tempdir(CLEANUP => 1);
  write_loader($dir);
  run_prog($dir, $Criteria, "", "ModA");
  run_prog($dir, $Criteria, "", qw( ModA ModB ));
  # this run adds no sub and leaves the stored count below the number of entries
  run_prog($dir, $Criteria, "", "ModA");
  run_prog($dir, $Criteria, "", qw( ModA ModB ModC ));
  my ($begin) = counts($dir, "prog.pl", 4);
  my (undef, $statements) = counts($dir, "prog.pl", 3);
  is_deeply $begin,      [4, 2, 1], "four runs: BEGIN counts of the loader";
  is_deeply $statements, [4, 4, 0], "four runs: statement counts of the if";
}

sub test_new_criteria_and_new_subs () {
  my $dir = tempdir(CLEANUP => 1);
  write_loader($dir);
  run_prog($dir, "statement", "", "ModA");
  run_prog($dir, $Criteria,   "", qw( ModA ModB ModC ));
  my ($begin) = counts($dir, "prog.pl", 4);
  my (undef, $statements) = counts($dir, "prog.pl", 3);
  is_deeply $begin,      [1, 1, 1], "new criteria: BEGIN counts of the loader";
  is_deeply $statements, [2, 2, 0], "new criteria: statement counts of the if";
}

sub write_required ($dir) {
  my $lib = File::Spec->catdir($dir, "lib");
  mkdir $lib or die "Cannot mkdir $lib: $!";
  write_file(File::Spec->catfile($lib, "F.pm"), <<'PERL');
package F;
our $c = 0;
eval "use strict; 1" if $ARGV[0];
$c = $c + 1;
$c = $c + 2;
eval "use warnings; 1" if ($ARGV[0] // 0) > 1;
1;
PERL
  write_file(File::Spec->catfile($dir, "prog.pl"), <<'PERL');
use lib "lib";
use F;
print $F::c, "\n";
PERL
}

sub check_required ($dir, $label, $runs, $begins) {
  for my $line (2, 4, 5, 7) {
    my (undef, $statements) = counts($dir, "lib/F.pm", $line);
    is_deeply $statements, [$runs], "$label: statement counts on line $line";
  }
  for my $line (sort keys %$begins) {
    my ($begin) = counts($dir, "lib/F.pm", $line);
    is_deeply $begin, $begins->{$line}, "$label: BEGIN counts on line $line";
  }
}

sub test_new_sub_in_required_file () {
  my $dir = tempdir(CLEANUP => 1);
  write_required($dir);
  run_prog($dir, $Criteria, "3\n");
  run_prog($dir, $Criteria, "3\n", 1);
  check_required($dir, "one new sub", 2, { 3 => [1], 6 => [] });
}

sub test_two_new_subs_in_required_file () {
  my $dir = tempdir(CLEANUP => 1);
  write_required($dir);
  run_prog($dir, $Criteria, "3\n");
  run_prog($dir, $Criteria, "3\n", 1);
  run_prog($dir, $Criteria, "3\n", 2);
  check_required($dir, "two new subs", 3, { 3 => [2], 6 => [1] });
}

sub main () {
  test_new_subs_on_other_lines;
  test_repeated_line_two_runs;
  test_repeated_line_three_runs;
  test_repeated_line_four_runs;
  test_new_criteria_and_new_subs;
  test_new_sub_in_required_file;
  test_two_new_subs_in_required_file;
  done_testing;
}

main;

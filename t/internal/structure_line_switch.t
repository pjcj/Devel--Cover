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
use Test::More import => [qw( diag done_testing is is_deeply like unlike )];

use Devel::Cover::DB ();

my $Root     = getcwd;
my $Lib      = File::Spec->rel2abs("blib/lib");
my $Arch     = File::Spec->rel2abs("blib/arch");
my $Cover    = File::Spec->rel2abs("bin/cover");
my $Criteria = "statement,branch,condition,subroutine";

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

sub cover_file ($dir, $name) {
  chdir $dir or die "Cannot chdir $dir: $!";
  my $file
    = Devel::Cover::DB->new(db => "cover_db")->merge_runs->cover->file($name);
  chdir $Root or die "Cannot chdir $Root: $!";
  $file
}

sub counts ($dir, $name, $line) {
  my $file = cover_file($dir, $name);
  [map $_->covered, ($file->statement->location($line) // [])->@*]
}

sub branch_counts ($dir, $name, $line) {
  my $branch = cover_file($dir, $name)->branch or return [];
  [map [$_->covered, $_->total], ($branch->location($line) // [])->@*]
}

sub condition_counts ($dir, $name, $line) {
  my $condition = cover_file($dir, $name)->condition or return [];
  [map [$_->covered, $_->total], ($condition->location($line) // [])->@*]
}

sub write_modules ($dir) {
  my $lib = File::Spec->catdir($dir, "lib");
  mkdir $lib or die "Cannot mkdir $lib: $!";
  write_file(File::Spec->catfile($lib, "First.pm"), <<'PERL');
package First;
sub a {
  my $p = 1;
  my $q = 2;
# line 20 "lib/Second.pm"
  my $r = 3;
  my $s = 4;
  if ($p) { $s++ }
  my $t = $p && $q;
# line 11 "lib/First.pm"
  my $u = $p || 0;
  $q = 3 if $p;
  $p + $q + $r + $s
}
sub b { my $y = 2; $y }
1;
PERL
  write_file(
    File::Spec->catfile($lib, "Second.pm"),
    join "",
    "package Second;\n",
    map("sub s$_ { my \$x = $_; \$x }\n", 1 .. 3),
    ("# filler\n") x 19, "1;\n",
  );
  write_file(File::Spec->catfile($dir, "prog.pl"), <<'PERL');
use lib "lib";
use First; use Second;
print First::a() + First::b() + Second::s1() + Second::s2() +
  Second::s3(), "\n";
PERL
}

sub check_lines ($dir, $label, $criterion, $count, $want) {
  for my $name (sort keys %$want) {
    for my $line (sort { $a <=> $b } keys $want->{$name}->%*) {
      is_deeply $count->($dir, $name, $line), $want->{$name}{$line},
        "$label: $criterion counts of $name on line $line";
    }
  }
}

sub check_counts ($dir, $label, $runs) {
  my $statements = {
    "lib/First.pm" => {
      (map { $_ => [] } 6 .. 9),
      (map { $_ => [1] } 3, 4, 11, 12, 13, 16),
      15 => [1, 1],
    },
    "lib/Second.pm" => {
      2  => [1, 1],
      3  => [1, 1],
      4  => [1, 1],
      20 => [1],
      21 => [1],
      22 => [1, 1],
      23 => [1],
      24 => [1],
    },
  };
  for my $lines (values %$statements) {
    $_ = [map $_ * $runs, @$_] for values %$lines;
  }
  my $none     = { map { $_ => [] } 1 .. 16 };
  my $branches = {
    "lib/First.pm"  => { %$none, 12 => [[1, 2]] },
    "lib/Second.pm" => { 20 => [], 21 => [], 22 => [[1, 2]] },
  };
  my $conditions = {
    "lib/First.pm"  => { %$none, 11 => [[1, 2]] },
    "lib/Second.pm" => { 20 => [], 21 => [], 23 => [[1, 3]] },
  };
  check_lines($dir, $label, "statement", \&counts,           $statements);
  check_lines($dir, $label, "branch",    \&branch_counts,    $branches);
  check_lines($dir, $label, "condition", \&condition_counts, $conditions);
}

sub test_line_switch_one_run () {
  my $dir = tempdir(CLEANUP => 1);
  write_modules($dir);
  run_prog($dir, $Criteria, "20\n");
  check_counts($dir, "one run", 1);
}

sub test_line_switch_two_runs () {
  my $dir = tempdir(CLEANUP => 1);
  write_modules($dir);
  run_prog($dir, $Criteria, "20\n") for 1 .. 2;
  check_counts($dir, "two runs", 2);
}

sub test_line_switch_no_warning () {
  my $dir = tempdir(CLEANUP => 1);
  write_modules($dir);
  run_prog($dir, $Criteria, "20\n");
  local %ENV = %ENV;
  delete @ENV{qw( DEVEL_COVER_SELF DEVEL_COVER_OPTIONS )};
  chdir $dir or die "Cannot chdir $dir: $!";
  my @cmd    = ($^X, "-I$Lib", "-I$Arch", $Cover, qw( -report text cover_db ));
  my $cmd    = join " ", map(qq("$_"), @cmd), "2>&1";
  my $out    = `$cmd`;
  my $status = $?;
  chdir $Root or die "Cannot chdir $Root: $!";
  is $status, 0, "no warning: cover exits 0" or diag $out;
  like $out,   qr|lib/First\.pm|, "no warning: cover reports lib/First.pm";
  unlike $out, qr/Warning/,       "no warning: cover gives no warning";
}

sub main () {
  test_line_switch_one_run;
  test_line_switch_two_runs;
  test_line_switch_no_warning;
  done_testing;
}

main;

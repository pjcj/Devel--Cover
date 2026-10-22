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

use File::Copy qw( copy );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is like ok )];

my $Root = Cwd::cwd();

use Devel::Cover::DB ();

my $Tmpdir = tempdir(CLEANUP => 1);

my $Script = <<'PERL';
my $x = 1;
my $y = 2;
my $z = $x + $y;
PERL

# Run a script under Devel::Cover and return the db path.
sub run_cover ($label, $db_label = $label) {
  my $script = File::Spec->catfile($Tmpdir, "$label.pl");
  my $db     = File::Spec->catdir($Tmpdir, "${db_label}_db");

  open my $fh, ">", $script or die "Cannot write $script: $!";
  print $fh $Script;
  close $fh or die "Cannot close $script: $!";

  my @inc = map { "-I$_" } "$Root/blib/arch", "$Root/blib/lib", "$Root/lib";

  system($^X, @inc, "-MDevel::Cover=-db,$db,-silent,1", $script) == 0
    or die "Failed to run $label under Devel::Cover: $?";

  $db
}

sub statement_counts ($db, $label) {
  my @counts;
  for my $run (values $db->{runs}->%*) {
    my ($file) = grep /$label\.pl$/, keys $run->{count}->%*;
    my $c      = $run->{count}{$file}{statement};
    $counts[$_] += $c->[$_] for 0 .. $#$c;
  }
  @counts
}

sub runs_entries ($db_path) {
  opendir my $dir, "$db_path/runs" or return;
  my @entries = grep { $_ ne "." && $_ ne ".." } readdir $dir;
  closedir $dir or die "Can't closedir $db_path/runs: $!";
  @entries
}

sub test_interrupted_merge () {
  my $db_path = run_cover("crash");

  my $db   = Devel::Cover::DB->new(db => $db_path);
  my $orig = \&Devel::Cover::DB::write;
  {
    no warnings "redefine";
    local *Devel::Cover::DB::write = sub {
      $orig->(@_);
      die "simulated crash\n";
    };
    eval { $db->merge_runs };
  }
  like $@, qr/simulated crash/, "merge interrupted after write";

  my $db2    = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  my @counts = statement_counts($db2, "crash");
  is @counts, 3, "crash: three statements";
  is $_,      1, "crash: statement executed once" for @counts;

  is runs_entries($db_path), 0, "crash: runs directory is empty";
}

sub test_interrupted_before_write () {
  my $db_path = run_cover("aside");

  my $db = Devel::Cover::DB->new(db => $db_path);
  {
    no warnings "redefine";
    local *Devel::Cover::DB::write = sub { die "simulated crash\n" };
    eval { $db->merge_runs };
  }
  like $@, qr/simulated crash/, "merge interrupted before write";
  my @entries = runs_entries($db_path);
  is @entries, 1, "aside: one entry left in runs";
  like $entries[0], qr/^\.merged\./, "aside: the run was set aside";
  ok !-e "$db_path/cover.15", "aside: no database written";

  my $db2    = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  my @counts = statement_counts($db2, "aside");
  is @counts, 3, "aside: three statements";
  is $_,      1, "aside: statement executed once" for @counts;

  is runs_entries($db_path), 0, "aside: runs directory is empty";
}

sub test_aside_with_earlier_merge () {
  my $db_path = run_cover("earlier");
  Devel::Cover::DB->new(db => $db_path)->merge_runs;
  run_cover("earlier");

  my $db = Devel::Cover::DB->new(db => $db_path);
  {
    no warnings "redefine";
    local *Devel::Cover::DB::write = sub { die "simulated crash\n" };
    eval { $db->merge_runs };
  }
  like $@, qr/simulated crash/, "earlier: merge interrupted before write";
  my @entries = runs_entries($db_path);
  is @entries, 1, "earlier: one entry left in runs";
  like $entries[0], qr/^\.merged\./, "earlier: the run is still set aside";

  my $db2    = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  my @counts = statement_counts($db2, "earlier");
  is @counts, 3, "earlier: three statements";
  is $_,      2, "earlier: statement executed twice" for @counts;

  is runs_entries($db_path), 0, "earlier: runs directory is empty";
}

sub merge_quietly ($db) {
  my $stderr = "";
  open my $save, ">&", \*STDERR or die "Cannot dup STDERR: $!";
  close STDERR or die "Cannot close STDERR: $!";
  open STDERR, ">", \$stderr or die "Cannot capture STDERR: $!";
  eval { $db->merge_runs };
  my $err = $@;
  close STDERR or die "Cannot close captured STDERR: $!";
  open STDERR, ">&", $save or die "Cannot restore STDERR: $!";
  close $save or die "Cannot close saved STDERR: $!";
  die $err if $err;
  $stderr
}

sub test_incomplete_run () {
  my $db_path = run_cover("incomplete");
  my $pending = "$db_path/runs/0000";
  mkdir $pending or die "Cannot mkdir $pending: $!";
  my $tmp = "$pending/cover.15.tmp.123";
  open my $fh, ">", $tmp or die "Cannot write $tmp: $!";
  close $fh or die "Cannot close $tmp: $!";

  my $db     = Devel::Cover::DB->new(db => $db_path);
  my $stderr = merge_quietly($db);
  my @counts = statement_counts($db, "incomplete");
  is @counts, 3, "incomplete: three statements";
  is $_,      1, "incomplete: statement executed once" for @counts;
  ok -d $pending, "incomplete: run without cover.15 is left alone";
  is $stderr, "", "incomplete: no warning printed";

  my $other = run_cover("incomplete", "incomplete2");
  my ($run) = runs_entries($other);
  copy("$other/runs/$run/cover.15", "$pending/cover.15")
    or die "Cannot copy cover.15: $!";

  my $db2 = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  @counts = statement_counts($db2, "incomplete");
  is @counts, 3, "incomplete: three statements after second merge";
  is $_,      2, "incomplete: statement executed twice" for @counts;
  is runs_entries($db_path), 0, "incomplete: runs directory is empty";
}

sub test_run_already_merged () {
  my $db_path = run_cover("twice");
  my ($run)   = runs_entries($db_path);
  my $saved   = File::Spec->catfile($Tmpdir, "twice.cover.15");
  copy("$db_path/runs/$run/cover.15", $saved) or die "Cannot copy cover.15: $!";

  Devel::Cover::DB->new(db => $db_path)->merge_runs;
  is runs_entries($db_path), 0, "twice: runs directory is empty";

  mkdir "$db_path/runs/$run" or die "Cannot mkdir $db_path/runs/$run: $!";
  copy($saved, "$db_path/runs/$run/cover.15")
    or die "Cannot copy cover.15 back: $!";

  my $db2    = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  my @counts = statement_counts($db2, "twice");
  is @counts,                3, "twice: three statements";
  is $_,                     1, "twice: statement executed once" for @counts;
  is runs_entries($db_path), 0, "twice: runs directory is empty again";
}

sub test_normal_merge () {
  my $db_path = run_cover("normal");

  my $db     = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  my @counts = statement_counts($db, "normal");
  is @counts, 3, "normal: three statements";
  is $_,      1, "normal: statement executed once" for @counts;

  is runs_entries($db_path), 0, "normal: runs directory is empty";
  ok -e "$db_path/merge.lock", "normal: merge lock file exists";
}

test_interrupted_merge;
test_interrupted_before_write;
test_aside_with_earlier_merge;
test_incomplete_run;
test_run_already_merged;
test_normal_merge;
done_testing;

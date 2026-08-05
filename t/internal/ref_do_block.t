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

use Cwd        qw( realpath );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing is )];

# Taking a reference to a do-block, "\do { $var = undef }", must return a
# reference to $var itself, as it does in plain perl.  Devel::Cover sets
# $^P & 0x004 (PERLDBf_NOOPT), which keeps a real enter/leave pair for the
# block, and pp_leave mortal-copies the block's value, so the reference
# points at a copy and assignment through it never reaches $var.  With more
# than one statement in the block plain perl also copies, and that must be
# preserved.  See GH-276.

my $Program = <<'PERL';
my $var;
my $foo_sr = \do { $var = undef };
$$foo_sr = "3:4:5";
print "ticket: ", (defined $var && $var eq $$foo_sr ? "set" : "unset"), "\n";

my $x;
my $rx = \do { $x = undef };
print "single: ", (\$x == $rx ? "same" : "copy"), "\n";

my $y;
my $ry = \do { $y = undef; };
print "trailing: ", (\$y == $ry ? "same" : "copy"), "\n";

my $z;
my $rz = \do { $z };
print "plain: ", (\$z == $rz ? "same" : "copy"), "\n";

my $d;
my $rd = \$d;
print "direct: ", (\$d == $rd ? "same" : "copy"), "\n";

my $m;
my $rm = \do { 1; $m = undef };
$$rm = "changed";
print "multi: ", (defined $m ? "set" : "unset"), "\n";
PERL

my $Expected = <<'TEXT';
ticket: set
single: same
trailing: same
plain: same
direct: same
multi: unset
TEXT

# Under taint mode perl keeps a real leave and copies even when optimising,
# so Devel::Cover must copy too.
my $Expected_taint = <<'TEXT';
ticket: unset
single: copy
trailing: copy
plain: copy
direct: same
multi: unset
TEXT

# A logop inside a do-block whose value is consumed by the block's leave
# makes Devel::Cover hijack the leave op for condition coverage.  Setting
# OPpLVALUE on a hijacked leave changes the pending-conditional key, which
# hashes op_private, so resolution fails and the run aborts.
my $Cond_program = <<'PERL';
my $q = 0;
my $r = do { $q || "default" };
print "r=$r\n";
PERL

my $Cond_expected = "r=default\n";

sub run_program ($label, $taint, $cover_options, $program, $expected) {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $prog   = File::Spec->catfile($tmpdir, "prog.pl");
  open my $fh, ">", $prog or die "Cannot write $prog: $!";
  print $fh $program;
  close $fh or die "Cannot close $prog: $!";

  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cover = "";
  if (defined $cover_options) {
    my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
    $cover = " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0,-ignore,."
      . ($cover_options ? ",$cover_options" : "");
  }
  my $out = `$^X$taint -Iblib/lib -Iblib/arch$cover $prog 2>&1`;
  is $?,   0,         "$label: run exits 0" or diag $out;
  is $out, $expected, "$label: refs to do-blocks match plain perl";
}

run_program "no coverage",       "",    undef,            $Program, $Expected;
run_program "default",           "",    "",               $Program, $Expected;
run_program "replace_ops 0",     "",    "-replace_ops,0", $Program, $Expected;
run_program "taint no coverage", " -T", undef, $Program, $Expected_taint;
run_program "taint default",     " -T", "",    $Program, $Expected_taint;

# On Windows Cwd chdirs inside abs_path, which taint forbids, killing the
# child at CHECK time under -replace_ops 0
run_program "taint replace_ops 0", " -T", "-replace_ops,0", $Program,
  $Expected_taint
  unless $^O eq "MSWin32";

run_program "cond default", "", "+select,prog", $Cond_program, $Cond_expected;
run_program "cond replace_ops 0", "", "-replace_ops,0,+select,prog",
  $Cond_program, $Cond_expected;

done_testing;

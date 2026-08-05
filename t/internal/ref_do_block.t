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

sub run_program ($label, $taint, $cover_options, $expected) {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $prog   = File::Spec->catfile($tmpdir, "prog.pl");
  open my $fh, ">", $prog or die "Cannot write $prog: $!";
  print $fh $Program;
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

run_program "no coverage",         "",    undef,            $Expected;
run_program "default",             "",    "",               $Expected;
run_program "replace_ops 0",       "",    "-replace_ops,0", $Expected;
run_program "taint no coverage",   " -T", undef,            $Expected_taint;
run_program "taint default",       " -T", "",               $Expected_taint;
run_program "taint replace_ops 0", " -T", "-replace_ops,0", $Expected_taint;

done_testing;

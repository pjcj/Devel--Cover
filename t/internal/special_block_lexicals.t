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

# A special block keeps a reference to every outer lexical it uses, and
# Devel::Cover keeps the block alive for the report, so without care the outer
# variable would only be freed at global destruction and DESTROY would run late.
my $Program = <<'PERL';
package Guard;
sub new { bless [ $_[1] ], $_[0] }
sub DESTROY { print "destroy $_[0][0]\n" }
package main;
{
  my $scope;
  BEGIN { $scope = Guard->new("block"); print "block BEGIN\n" }
  print "block body\n";
}
print "after block\n";
sub f {
  no warnings "closure";
  my $x;
  BEGIN { $x = Guard->new("sub") }
  print "f body\n";
}
f();
print "after f\n";
{
  my $r;
  BEGIN { $r = Guard->new("return"); return }
  print "return body\n";
}
print "after return\n";
require Mod;
print "after require\n";
END { print "END\n" }
PERL

my $Module = <<'PERL';
package Mod;
my $file;
BEGIN { $file = Guard->new("module"); print "Mod BEGIN\n" }
print "Mod body\n";
sub keep { }
1;
PERL

my $Expected = <<'TEXT';
block BEGIN
block body
destroy block
after block
f body
destroy sub
after f
return body
destroy return
after return
Mod BEGIN
Mod body
destroy module
after require
END
TEXT

# Plain perl frees UNITCHECK, CHECK and INIT blocks at the end of the run, so
# a lexical they capture lives until then.  Devel::Cover releases the capture
# as soon as the block has run, so the variable goes when its scope ends.
my $Phase_program = <<'PERL';
package Guard;
sub new { bless [ $_[1] ], $_[0] }
sub DESTROY { print "destroy $_[0][0]\n" }
package main;
{
  my ($u, $c, $i);
  UNITCHECK { $u = Guard->new("unitcheck") }
  CHECK     { $c = Guard->new("check") }
  INIT      { $i = Guard->new("init") }
  print "block body\n";
}
print "after block\n";
END { print "END\n" }
PERL

my $Phase_expected = <<'TEXT';
block body
destroy init
destroy check
destroy unitcheck
after block
END
TEXT

# Under a debugger perl calls DB::sub for every sub, special blocks included,
# so a statement runs between perl saving a block and entering it.
my $Stub = <<'PERL';
package Devel::DCStub;
package DB;
sub DB  { }
sub sub { no strict "refs"; &$DB::sub }
1;
PERL

sub write_file ($path, $text) {
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $text;
  close $fh or die "Cannot close $path: $!";
}

sub setup () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  write_file(File::Spec->catfile($tmpdir, "prog.pl"),  $Program);
  write_file(File::Spec->catfile($tmpdir, "phase.pl"), $Phase_program);
  write_file(File::Spec->catfile($tmpdir, "Mod.pm"),   $Module);
  my $stubdir = File::Spec->catdir($tmpdir, "Devel");
  mkdir $stubdir or die "Cannot mkdir $stubdir: $!";
  write_file(File::Spec->catfile($stubdir, "DCStub.pm"), $Stub);
  $tmpdir
}

sub run_program (
  $tmpdir, $label, $script, $switches, $cover_options, $expected
) {
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cover = "";
  if (defined $cover_options) {
    my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
    $cover
      = " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0"
      . ",+select,$script,+select,Mod"
      . ($cover_options ? ",$cover_options" : "");
  }
  my $prog = File::Spec->catfile($tmpdir, "$script.pl");
  my $out  = `$^X -Iblib/lib -Iblib/arch -I$tmpdir$switches$cover $prog 2>&1`;
  is $?,   0,         "$label: run exits 0" or diag $out;
  is $out, $expected, "$label: destruction order";
}

sub main () {
  my $tmpdir = setup;
  my @cases  = (
    ["no coverage",            "prog",  "",           undef],
    ["default",                "prog",  "",           ""],
    ["replace_ops 0",          "prog",  "",           "-replace_ops,0"],
    ["debugger default",       "prog",  " -d:DCStub", ""],
    ["debugger replace_ops 0", "prog",  " -d:DCStub", "-replace_ops,0"],
    ["phases default",         "phase", "",           ""],
    ["phases replace_ops 0",   "phase", "",           "-replace_ops,0"],
  );
  for my $case (@cases) {
    my ($label, $script, $switches, $options) = @$case;
    run_program $tmpdir, $label, $script, $switches, $options,
      $script eq "prog" ? $Expected : $Phase_expected;
  }
  done_testing;
}

main;

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
use File::Path qw( make_path );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing is like )];
use Devel::Cover::Test::Showcase qw( run_cover );

my $Stub = <<'PERL';
package Devel::DCStub;
package DB;
sub DB  { }
sub sub { no strict "refs"; &$DB::sub }
1;
PERL

my $Helper = <<'PERL';
package Helper;
my $loaded = 1;
1;
PERL

# Clearing $^P before the require makes Helper compile with OP_NEXTSTATE ops
# although the pre-compiled main script runs OP_DBSTATE ops. With
# -replace_ops 0 the collecting decision comes from the %Files cache, which
# add_cvs sweeps populate during real runs - seed it here. Helper's
# OP_NEXTSTATE ops then turn collection off, and only the OP_DBSTATE refresh
# can turn it back on for the statements after the require.
my $Target = <<'PERL';
use File::Basename ();
my $dir = File::Basename::dirname(__FILE__);
$Devel::Cover::Files{ +__FILE__ } = 1;
$Devel::Cover::Files{"$dir/Helper.pm"} = 0;
my $x = 1;
$^P = 0;
require Helper;
my $y = $x + 1;
my $z = $y + 1;
print "ok\n";
PERL

# Under an external debugger statement ops compile as OP_DBSTATE, and with
# -replace_ops 0 the runops_cover loop must refresh the collecting state for
# them just as it does for OP_NEXTSTATE, or statements are lost.
sub main () {
  my $tmpdir  = realpath(tempdir(CLEANUP => 1));
  my $stubdir = File::Spec->catdir($tmpdir, "Devel");
  make_path($stubdir);

  my %write = (
    File::Spec->catfile($stubdir, "DCStub.pm") => $Stub,
    File::Spec->catfile($tmpdir,  "Helper.pm") => $Helper,
    File::Spec->catfile($tmpdir,  "target.pl") => $Target,
  );
  for my $path (sort keys %write) {
    open my $fh, ">", $path or die "Cannot write $path: $!";
    print $fh $write{$path};
    close $fh or die "Cannot close $path: $!";
  }

  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  my $target   = File::Spec->catfile($tmpdir, "target.pl");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$tmpdir -d:DCStub"
    . " -MDevel::Cover=-replace_ops,0"
    . ",-db,$cover_db,-silent,1,-merge,0"
    . " $target 2>&1";
  my $out = `$cmd`;
  is $?,   0,      "covered run under debugger stub exits 0" or diag $out;
  is $out, "ok\n", "target runs normally";

  my ($report, $exit) = run_cover(
    "--report", "text", "-coverage", "statement", "--silent", $cover_db,
  );
  is $exit, 0, "cover --report text exits 0" or diag $report;

  my ($stmt) = $report =~ /target\.pl\s+([\d.]+)/;
  is $stmt, "100.0", "all target statements covered" or diag $report;

  done_testing;
}

main;

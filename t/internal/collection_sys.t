#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();  ## no perlimports
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use File::Temp ();

use Test::More import => [qw( done_testing is like plan )];

BEGIN {
  plan skip_all => "Devel::Cover::Collection requires Perl 5.42" if $] < 5.042;
  plan skip_all => "Devel::Cover::Collection is not portable to Windows"
    if $^O eq "MSWin32";
  for my $module (qw( Template Parallel::Iterator JSON::MaybeXS )) {
    plan skip_all => "$module required for this test"
      unless eval "require $module; 1";
  }
}

use Devel::Cover::Collection ();

sub bsys_warnings ($collection, @command) {
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_ };
  my $output = $collection->bsys(@command);
  ($output, join "", @warnings)
}

sub test_success () {
  my ($output, $warned) = bsys_warnings(
    Devel::Cover::Collection->new,
    $^X, "-e", 'print "stdout line\n"; warn "stderr line\n"',
  );
  like $output, qr/stdout line/, "success returns stdout";
  like $output, qr/stderr line/, "success returns merged stderr";
  is $warned, "", "success warns nothing";
}

sub test_failure () {
  # uc keeps the expected text out of the command echoed by the warning
  my ($output, $warned) = bsys_warnings(
    Devel::Cover::Collection->new,
    $^X,
    "-e",
    'print uc("stdout detail"), "\n"; warn uc("stderr detail"), "\n"; exit(3)',
  );
  is $output, "", "failure returns empty string";
  like $warned, qr/Error running/, "failure is warned";
  like $warned, qr/exit 3/,        "warning reports the exit status";
  like $warned, qr/STDOUT DETAIL/, "warning includes the command's stdout";
  like $warned, qr/STDERR DETAIL/, "warning includes the command's stderr";
}

sub test_timeout () {
  my ($output, $warned) = bsys_warnings(
    Devel::Cover::Collection->new(timeout => 1),
    $^X, "-e", '$| = 1; print uc("before hang"), "\n"; sleep 30',
  );
  is $output, "", "timeout returns empty string";
  like $warned, qr/Timed out/, "timeout is warned";
  like $warned, qr/BEFORE HANG/,
    "timeout warning includes the command's output";
  like $warned, qr/killed [1-9]\d* process/, "timeout kills the hung command";
}

sub test_escaped_child () {
  my $tmp    = File::Temp->newdir;
  my $marks  = "$tmp/marks";
  my $script = "$tmp/escape.pl";
  open my $sfh, ">", $script or die "Can't open $script: $!";
  print $sfh <<'PERL';
use Devel::Cover::Collection ();
my ($marks) = @ARGV;
my $c = Devel::Cover::Collection->new;
$SIG{__WARN__} = sub { };
for (1, 2) { eval { $c->fsys("/no/such/command", "x") } }
open my $fh, ">>", $marks or die "Can't open $marks: $!";
print $fh "$$\n";
close $fh or die "Can't close $marks: $!";
PERL
  close $sfh or die "Can't close $script: $!";
  system $^X, "-I$FindBin::Bin/../../lib", $script, $marks;
  open my $mfh, "<", $marks or die "Can't open $marks: $!";
  my @pids = <$mfh>;
  close $mfh or die "Can't close $marks: $!";
  is @pids, 1, "a failed exec never escapes the child";
}

sub test_fsys_dies () {
  my $c = Devel::Cover::Collection->new;
  {
    local $SIG{__WARN__} = sub { };
    eval { $c->fsys("/no/such/command", "x") };
  }
  like $@, qr/^Can't run/, "fsys dies in the parent on a failed exec";
}

sub main () {
  test_success;
  test_failure;
  test_timeout;
  test_escaped_child;
  test_fsys_dies;
}

main;
done_testing;

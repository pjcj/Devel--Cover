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

my $Collection = Devel::Cover::Collection->new;

my ($Output, $Warned) = bsys_warnings(
  $Collection, $^X, "-e", 'print "stdout line\n"; warn "stderr line\n"'
);
like $Output, qr/stdout line/, "success returns stdout";
like $Output, qr/stderr line/, "success returns merged stderr";
is $Warned, "", "success warns nothing";

# uc keeps the expected text out of the command echoed by the warning
($Output, $Warned) = bsys_warnings($Collection, $^X, "-e",
  'print uc("stdout detail"), "\n"; warn uc("stderr detail"), "\n"; exit(3)');
is $Output, "", "failure returns empty string";
like $Warned, qr/Error running/, "failure is warned";
like $Warned, qr/exit 3/,        "warning reports the exit status";
like $Warned, qr/STDOUT DETAIL/, "warning includes the command's stdout";
like $Warned, qr/STDERR DETAIL/, "warning includes the command's stderr";

my $Quick = Devel::Cover::Collection->new(timeout => 1);
($Output, $Warned) = bsys_warnings(
  $Quick, $^X, "-e", '$| = 1; print uc("before hang"), "\n"; sleep 30'
);
is $Output, "", "timeout returns empty string";
like $Warned, qr/Timed out/,   "timeout is warned";
like $Warned, qr/BEFORE HANG/, "timeout warning includes the command's output";
like $Warned, qr/killed [1-9]\d* process/, "timeout kills the hung command";

my $Tmp    = File::Temp->newdir;
my $Marks  = "$Tmp/marks";
my $Script = "$Tmp/escape.pl";
open my $Sfh, ">", $Script or die "Can't open $Script: $!";
print $Sfh <<'PERL';
use Devel::Cover::Collection ();
my ($marks) = @ARGV;
my $c = Devel::Cover::Collection->new;
$SIG{__WARN__} = sub { };
for (1, 2) { eval { $c->fsys("/no/such/command", "x") } }
open my $fh, ">>", $marks or die "Can't open $marks: $!";
print $fh "$$\n";
close $fh or die "Can't close $marks: $!";
PERL
close $Sfh or die "Can't close $Script: $!";
system $^X, "-I$FindBin::Bin/../../lib", $Script, $Marks;
open my $Mfh, "<", $Marks or die "Can't open $Marks: $!";
my @Pids = <$Mfh>;
close $Mfh or die "Can't close $Marks: $!";
is @Pids, 1, "a failed exec never escapes the child";

{
  local $SIG{__WARN__} = sub { };
  eval { $Collection->fsys("/no/such/command", "x") };
}
like $@, qr/^Can't run/, "fsys dies in the parent on a failed exec";

done_testing;

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

use Config     qw( %Config );
use Cwd        qw( getcwd realpath );
use File::Path qw( make_path );
use File::Temp qw( tempdir );

use Test::More import => [qw( done_testing is like ok plan )];

BEGIN {
  plan skip_all => "Devel::Cover::Collection requires Perl 5.42" if $] < 5.042;
  plan skip_all => "Devel::Cover::Collection is not portable to Windows"
    if $^O eq "MSWin32";
  for my $module (qw( Template Parallel::Iterator JSON::MaybeXS )) {
    plan skip_all => "$module required for this test"
      unless eval "require $module; 1";
  }
}

use Devel::Cover::Collection   ();
use Devel::Cover::DB::IO::JSON ();

my $Root      = realpath("$FindBin::Bin/../..");
my $Tmp       = tempdir CLEANUP => 1;
my $Build_dir = "$Tmp/build/Foo-Bar-0.01-0";

make_path "$Build_dir/lib/Foo";

open my $fh, ">", "$Build_dir/Makefile.PL" or die "Can't open Makefile.PL: $!";
print $fh <<'EOS';
use ExtUtils::MakeMaker;
WriteMakefile(NAME => "Foo::Bar", VERSION => "0.01");
EOS
close $fh or die "Can't close Makefile.PL: $!";

open $fh, ">", "$Build_dir/lib/Foo/Bar.pm" or die "Can't open Bar.pm: $!";
print $fh <<'EOS';
package Foo::Bar;
use strict;
use warnings;
sub add {
  my ($x, $y) = @_;
  return $x + $y if defined $x;
  0
}
1;
EOS
close $fh or die "Can't close Bar.pm: $!";

delete local @ENV{qw( DEVEL_COVER_SELF HARNESS_PERL_SWITCHES PERL5OPT )};

my $Cwd = getcwd;
chdir $Build_dir or die "Can't chdir $Build_dir: $!";
plan skip_all => "perl Makefile.PL failed"
  if system "'$^X' Makefile.PL >mpl.out 2>&1";
plan skip_all => "$Config{make} failed"
  if system "$Config{make} >make.out 2>&1";
chdir $Cwd or die "Can't chdir $Cwd: $!";

my $Collection = Devel::Cover::Collection->new(
  bin_dir     => "$Root/bin",
  results_dir => "$Tmp/results",
  local       => 1,
);

open my $Saved_stdout, ">&", \*STDOUT       or die "Can't save STDOUT: $!";
open STDOUT,           ">",  "$Tmp/run.out" or die "Can't redirect STDOUT: $!";
my $Err = do { local $@; eval { $Collection->run($Build_dir) }; $@ };
open STDOUT, ">&", $Saved_stdout or die "Can't restore STDOUT: $!";
chdir $Cwd or die "Can't chdir $Cwd: $!";

my $Rdir = "$Tmp/results/Foo-Bar-0.01";
is $Err, "", "run succeeds for a distribution without tests";
ok -d $Rdir,              "results are published";
ok -e "$Rdir/index.html", "html report is generated";
ok -e "$Rdir/cover.json", "json summary is generated";

my $Json    = Devel::Cover::DB::IO::JSON->new->read("$Rdir/cover.json");
my $Summary = $Json->{summary} // {};
ok $Summary->{"blib/lib/Foo/Bar.pm"}, "untested module appears in summary";

if (eval { require PPI; 1 }) {
  my $statement = $Summary->{Total}{statement} // {};
  is $statement->{covered}, 0, "no statements are covered";
  ok $statement->{total}, "statement total is estimated";
  is $statement->{percentage}, 0, "statement coverage is 0%";
}

done_testing;

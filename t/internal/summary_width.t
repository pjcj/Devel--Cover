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

use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is like ok )];

my $Root = Cwd::cwd();

use Devel::Cover::DB            ();
use Devel::Cover::DB::Structure ();

## no critic (Subroutines::ProtectPrivateSubs, Variables::ProtectPrivateVars)

my $Tmpdir = tempdir(CLEANUP => 1);

sub trimmed ($f, $len) { Devel::Cover::DB::trimmed_file($f, $len) }

sub test_trimmed_file () {
  my $f = "lib/Devel/Cover/DB.pm";
  is trimmed($f, -26), $f, "negative length leaves the name alone";
  for my $len (0 .. 3) {
    is trimmed($f, $len), $f, "length $len leaves the name alone";
  }
  is trimmed($f,      10), "...r/DB.pm", "ordinary trim unchanged";
  is trimmed("short", 10), "short", "name shorter than the length untouched";
}

sub test_file_width () {
  is Devel::Cover::DB::_file_width(200, 9, 30), 30,
    "wide terminal uses the longest name's width";
  is Devel::Cover::DB::_file_width(80, 8, 100), 21,
    "long names get the space the columns leave";
  is Devel::Cover::DB::_file_width(66, 9, 30), 12,
    "no space left falls back to the minimum";
  is Devel::Cover::DB::_file_width(59, 8, 30), 12,
    "everyday tmux split falls back to the minimum";
  is Devel::Cover::DB::_file_width(40, 9, 30), 12,
    "narrow terminal falls back to the minimum";
  is Devel::Cover::DB::_file_width(40, 9, 8), 8,
    "names shorter than the minimum keep their own width";
}

sub run_cover ($label, $script_content) {
  my $script = File::Spec->catfile($Tmpdir, "$label.pl");
  my $db     = File::Spec->catdir($Tmpdir, "${label}_db");

  open my $fh, ">", $script or die "Cannot write $script: $!";
  print $fh $script_content;
  close $fh or die "Cannot close $script: $!";

  my @inc = map { "-I$_" } "$Root/blib/arch", "$Root/blib/lib", "$Root/lib";

  system($^X, @inc, "-MDevel::Cover=-db,$db,-silent,1", $script) == 0
    or die "Failed to run $label under Devel::Cover: $?";

  ($db, $script)
}

sub test_narrow_summary () {
  my ($db_path, $script) = run_cover("nw", <<'PERL');
my $x = 1;
my $y = $x ? 2 : 3;
PERL

  my $st = Devel::Cover::DB::Structure->new(base => $db_path);
  $st->read_all;

  my $db = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  $db->set_structure($st);

  my ($output, @warnings);
  {
    open my $fh, ">", \$output or die "Cannot open scalar ref: $!";
    local *STDOUT = $fh;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    no warnings "redefine";
    local *Devel::Cover::DB::_term_width = sub () { 40 };
    $db->print_summary(
      undef,
      [qw( statement branch condition subroutine )],
      { force => 1 },
    );
    close $fh or die "Cannot close scalar ref: $!";
  }

  like $output, qr/^\S*nw\.pl\s/m, "file row keeps its name";
  like $output, qr/^Total\s/m,     "total row keeps its name";
  is grep(/Negative repeat count/, @warnings), 0,
    "no negative repeat count warnings";
}

sub main () {
  test_trimmed_file;
  test_file_width;
  test_narrow_summary;
}

main;
done_testing;

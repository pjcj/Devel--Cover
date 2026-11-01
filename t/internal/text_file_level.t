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
use Test::More import => [qw( done_testing like unlike )];

use Devel::Cover::DB            ();
use Devel::Cover::DB::Structure ();
use Devel::Cover::Report::Text  ();

my $Root   = Cwd::cwd();
my $Tmpdir = tempdir(CLEANUP => 1);

my $Source = <<'PERL';
use strict;
my $x = 1;
if ($x) { $x++ }
sub named { $_[0] ? 1 : 0 }
named($x);
PERL

my $No_subs_source = <<'PERL';
my $x = @ARGV;
my $y = $x ? 1 : 2;
PERL

sub run_cover ($label, $source) {
  my $script = File::Spec->catfile($Tmpdir, "$label.pl");
  my $db     = File::Spec->catdir($Tmpdir, "${label}_db");

  open my $fh, ">", $script or die "Cannot write $script: $!";
  print $fh $source;
  close $fh or die "Cannot close $script: $!";

  my @inc = map "-I$_", "$Root/blib/arch", "$Root/blib/lib", "$Root/lib";
  system($^X, @inc, "-MDevel::Cover=-db,$db,-silent,1", $script) == 0
    or die "Failed to run $label under Devel::Cover: $?";
  $db
}

sub text_report ($label, $source, @show) {
  my $db_path = run_cover($label, $source);
  my $st      = Devel::Cover::DB::Structure->new(base => $db_path);
  $st->read_all;
  my $db = Devel::Cover::DB->new(db => $db_path)->merge_runs;
  $db->set_structure($st);
  my @criteria = qw( statement branch condition subroutine );
  $db->calculate_summary(map { $_ => 1 } @criteria);

  my $options = {
    show        => { map { $_ => 1 } @show },
    file        => [$db->cover->items],
    annotations => [],
  };

  my $output;
  open my $fh, ">", \$output or die "Cannot open scalar ref: $!";
  local *STDOUT = $fh;
  Devel::Cover::Report::Text->report($db, $options);
  close $fh or die "Cannot close scalar ref: $!";
  $output
}

sub covered_section ($output) {
  $output =~ /^Covered Subroutines\n-+\n\n(.*?)(?:\n\n|\z)/ms ? $1 : ""
}

sub test_file_level_row () {
  my $covered = covered_section(text_report("fl_text", $Source, "subroutine"));
  like $covered, qr/^\{file-level code\}\s+2\s+\d+\.\d\s+\S*fl_text\.pl:1$/m,
    "file-level row has a blank count, its CC, SCAR and location";
  like $covered, qr/^named\s+1\s+2\s+\d+\.\d\s+\S*fl_text\.pl:4$/m,
    "named sub keeps its count, CC and SCAR";
  like $covered, qr/^BEGIN\s+\d+\s+\S*fl_text\.pl:1$/m,
    "BEGIN row keeps its count with blank CC and SCAR";
  unlike $covered, qr/^BEGIN\s+\d+\s+\d+\s+\d+\.\d/m,
    "no BEGIN row has CC or SCAR";
}

sub test_file_level_row_without_subs () {
  my $output  = text_report("fl_nosubs", $No_subs_source, "subroutine");
  my $covered = covered_section($output);
  like $covered, qr/^\{file-level code\}\s+2\s+\d+\.\d\s+\S*fl_nosubs\.pl:1$/m,
    "file-level row appears in a file with no subroutine records";
}

sub main () {
  test_file_level_row;
  test_file_level_row_without_subs;
  done_testing;
}

main

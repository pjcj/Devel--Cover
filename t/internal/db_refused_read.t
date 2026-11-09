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

use File::Temp qw( tempdir );
use List::Util qw( first );
use Test::More import => [qw( diag done_testing is_deeply like ok plan )];

use Devel::Cover::DB ();

my $Other = first {
  my $f = $_;
  eval {
    $f eq "Sereal"
      ? (require Sereal::Decoder, require Sereal::Encoder)
      : require JSON::MaybeXS;
    1
  }
} qw( Sereal JSON );

plan skip_all => "needs Storable and one of Sereal or JSON"
  unless $Other && eval { require Storable; 1 };

my $Run_name = "1000.1.00001";
my $Run      = {
  OS        => $^O,
  perl      => "5.26.3",
  dir       => "/x",
  run       => "t.pl",
  name      => "x",
  version   => "1",
  start     => 1,
  finish    => 2,
  collected => ["statement"],
  count     => { "a.pl" => { statement => [1, 1] } },
  digests   => { "a.pl" => "abc" },
};

sub write_run ($dir) {
  mkdir "$dir/runs" or die "Cannot mkdir $dir/runs: $!";
  local $ENV{DEVEL_COVER_DB_FORMAT} = "Storable";
  Devel::Cover::DB->new(
    base => $dir,
    db   => "$dir/runs/$Run_name",
    runs => { $Run_name => $Run },
  )->write;
}

sub write_main ($dir) {
  local $ENV{DEVEL_COVER_DB_FORMAT} = "Storable";
  Devel::Cover::DB->new(
    base => $dir,
    db   => $dir,
    runs => { "999.1.00001" => { %$Run, name => "old" } },
  )->write;
}

sub magic ($file) {
  open my $fh, "<", $file or die "Cannot open $file: $!";
  binmode $fh;
  read $fh, my $magic, 4;
  close $fh or die "Cannot close $file: $!";
  $magic
}

sub test_refused_main_db () {
  local $Storable::flags = undef;
  my $dir = tempdir(CLEANUP => 1);
  write_run($dir);
  write_main($dir);

  local $ENV{DEVEL_COVER_DB_FORMAT} = $Other;
  my $ok = eval { Devel::Cover::DB->new(db => $dir); 1 };
  ok !$ok, "$Other read of a Storable main database dies";
  like $@, qr/DEVEL_COVER_DB_FORMAT=Storable/, "the error names the setting";
  like magic("$dir/cover.15"), qr/^pst0/,      "the main database is untouched";
  ok -e "$dir/runs/$Run_name/cover.15", "the run is kept";
}

sub test_refused_run () {
  local $Storable::flags = undef;
  my $dir = tempdir(CLEANUP => 1);
  write_run($dir);

  local $ENV{DEVEL_COVER_DB_FORMAT} = $Other;
  my $db = Devel::Cover::DB->new(db => $dir);
  my $ok = eval { $db->merge_runs; 1 };
  ok !$ok, "$Other merge of a Storable run dies";
  like $@, qr/DEVEL_COVER_DB_FORMAT=Storable/, "the error names the setting";
  ok !-e "$dir/cover.15", "no main database is written";
  my $run = "$dir/runs/$Run_name/cover.15";
  ok -e $run, "the run is kept";
  like magic($run), qr/^pst0/, "the run is untouched" if -e $run;
}

sub test_storable_configured_reads () {
  local $Storable::flags = undef;
  my $dir = tempdir(CLEANUP => 1);
  write_run($dir);
  write_main($dir);

  local $ENV{DEVEL_COVER_DB_FORMAT} = "Storable";
  my $db = eval { Devel::Cover::DB->new(db => $dir)->merge_runs };
  ok $db, "Storable merge of a Storable database lives" or diag $@;
  my $runs = $db ? $db->{runs} : {};
  is_deeply [sort keys %$runs], [$Run_name, "999.1.00001"],
    "the merged database holds both runs";
}

sub main () {
  test_refused_main_db;
  test_refused_run;
  test_storable_configured_reads;
  done_testing;
}

main;

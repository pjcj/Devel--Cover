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

use File::Spec ();
use File::Temp qw( tempdir );
use List::Util qw( any );
use Test::More import =>
  [qw( diag done_testing is is_deeply like ok skip unlike )];

use Devel::Cover::DB::IO ();

my $Tmpdir = tempdir(CLEANUP => 1);

my @Formats = grep {
  my $f = $_;
  eval {
        $f eq "Sereal" ? (require Sereal::Decoder, require Sereal::Encoder)
      : $f eq "JSON"   ? require JSON::MaybeXS
      :                  require Storable;
    1
  }
} qw( Sereal JSON Storable );

my $Data = {
  runs  => { r1 => { count => { "a.pl" => [1, 2, 3] } } },
  files => ["a.pl", "b.pl"],
};

sub path ($name) { File::Spec->catfile($Tmpdir, $name) }

sub slurp ($file) {
  open my $fh, "<", $file or die "Cannot open $file: $!";
  binmode $fh;
  local $/;
  my $content = <$fh>;
  close $fh or die "Cannot close $file: $!";
  $content
}

sub magic_matches ($file, $format) {
  open my $fh, "<", $file or die "Cannot open $file: $!";
  binmode $fh;
  read $fh, my $magic, 4;
  close $fh or die "Cannot close $file: $!";
      $format eq "Sereal"   ? $magic =~ /^=/
    : $format eq "Storable" ? $magic =~ /^pst0/
    :                         $magic =~ /^\s*[\[{]/
}

sub test_round_trip () {
  for my $format (@Formats) {
    local $ENV{DEVEL_COVER_DB_FORMAT} = $format;
    my $file = path("rt_$format");
    my $io   = Devel::Cover::DB::IO->new;
    $io->write($Data, $file);
    is_deeply $io->read($file), $Data, "round trip with $format";
  }
}

sub test_output_separators () {
  for my $format (@Formats) {
    local $ENV{DEVEL_COVER_DB_FORMAT} = $format;
    my $file = path("sep_$format");
    my $io   = Devel::Cover::DB::IO->new;
    {
      local $\ = "XX";
      $io->write($Data, $file);
    }
    my $got = eval { $io->read($file) };
    is_deeply $got, $Data,
      "round trip with $format with the output record separator set"
      or diag $@;
    unlike slurp($file), qr/XX\z/, "$format file does not end in the separator";
  }
}

sub test_cross_format_read () {
  SKIP: {
    skip "needs at least two formats", 1 if @Formats < 2;
    for my $write (@Formats) {
      for my $read (grep $_ ne $write, @Formats) {
        my $file = path("xf_${write}_$read");
        {
          local $ENV{DEVEL_COVER_DB_FORMAT} = $write;
          Devel::Cover::DB::IO->new->write($Data, $file);
        }
        local $ENV{DEVEL_COVER_DB_FORMAT} = $read;
        my $got = eval { Devel::Cover::DB::IO->new->read($file) };
        is_deeply $got, $Data, "write $write, read $read" or diag $@;
      }
    }
  }
}

sub test_format_argument () {
  SKIP: {
    skip "needs JSON", 1 unless any { $_ eq "JSON" } @Formats;
    local $ENV{DEVEL_COVER_DB_FORMAT};
    my $file = path("fmt_arg");
    Devel::Cover::DB::IO->new(format => "JSON")->write($Data, $file);
    ok magic_matches($file, "JSON"), "format argument selects JSON writes";
  }
}

sub test_env_overrides_argument () {
  SKIP: {
    skip "needs at least two formats", 1 if @Formats < 2;
    my ($env, $arg) = @Formats[0, 1];
    local $ENV{DEVEL_COVER_DB_FORMAT} = $env;
    my $file = path("env_wins");
    Devel::Cover::DB::IO->new(format => $arg)->write($Data, $file);
    ok magic_matches($file, $env), "environment overrides format argument";
  }
}

sub test_sereal_refuses_objects () {
  SKIP: {
    skip "needs Sereal", 1 unless any { $_ eq "Sereal" } @Formats;
    my $file = path("sereal_object");
    my $obj  = bless {}, "Devel::Cover::DB::IO::Test::Object";
    open my $fh, ">", $file or die "Cannot write $file: $!";
    binmode $fh;
    print $fh Sereal::Encoder->new({})
      ->encode({ runs => {}, files => [], x => $obj });
    close $fh or die "Cannot close $file: $!";

    for my $format (@Formats) {
      local $ENV{DEVEL_COVER_DB_FORMAT} = $format;
      my $got = eval { Devel::Cover::DB::IO->new->read($file) };
      ok !defined $got, "$format read of a Sereal object returns nothing";
      like $@, qr/refuse_objects/, "$format read refuses a Sereal object";
    }
  }
}

sub test_garbage_still_dies () {
  my $file = path("garbage");
  open my $fh, ">", $file or die "Cannot write $file: $!";
  print $fh "this is not valid serialised data";
  close $fh or die "Cannot close $file: $!";

  my $ok = eval { Devel::Cover::DB::IO->new->read($file); 1 };
  ok !$ok, "garbage data still dies";
}

sub test_unrecognised_format_dies () {
  local $ENV{DEVEL_COVER_DB_FORMAT} = "Bogus";
  my $ok = eval { Devel::Cover::DB::IO->new; 1 };
  ok !$ok, "unrecognised format dies";
  like $@, qr/Unrecognised DB format/, "unrecognised format names the error";
}

sub main () {
  test_round_trip;
  test_output_separators;
  test_cross_format_read;
  test_format_argument;
  test_env_overrides_argument;
  test_sereal_refuses_objects;
  test_garbage_still_dies;
  test_unrecognised_format_dies;
  done_testing;
}

main;

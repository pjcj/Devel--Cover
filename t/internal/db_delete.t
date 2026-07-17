#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# delete removes the contents of a coverage database. It must refuse to
# touch a directory that does not look like a coverage database - it is
# called unguarded from coverage start-up when -merge,0 is given, so a
# mistyped -db path must not destroy unrelated data.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use File::Path qw( make_path );
use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( done_testing is isnt like ok )];

use Devel::Cover::DB ();

my $Tmpdir = tempdir(CLEANUP => 1);
my $N      = 0;

sub dir_with (@entries) {
  my $path = File::Spec->catdir($Tmpdir, "dir" . ++$N);
  make_path($path);
  for my $entry (@entries) {
    if ($entry =~ s|/$||) {
      make_path(File::Spec->catdir($path, $entry));
    } else {
      my $file = File::Spec->catfile($path, $entry);
      open my $fh, ">", $file or die "Cannot write $file: $!";
      print $fh "data\n";
      close $fh or die "Cannot close $file: $!";
    }
  }
  $path
}

sub entries ($path) {
  opendir my $dir, $path or die "Cannot opendir $path: $!";
  my @entries = grep !/^\.\.?$/, readdir $dir;
  closedir $dir or die "Cannot closedir $path: $!";
  @entries
}

sub warnings_from ($code) {
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_ };
  $code->();
  join "", @warnings
}

sub test_class_method_refuses_foreign_directory () {
  my $path     = dir_with("precious.txt");
  my $warnings = warnings_from sub { eval { Devel::Cover::DB->delete($path) } };
  like $@, qr/not a coverage database/,
    "delete: class method refuses a foreign directory";
  like $warnings, qr/found precious\.txt/,
    "delete: class method names the unexpected file";
  ok -s File::Spec->catfile($path, "precious.txt"),
    "delete: class method leaves the contents alone";
}

sub test_instance_method_refuses_foreign_directory () {
  my $path = dir_with("precious.txt");
  my $db   = Devel::Cover::DB->new;
  $db->{db} = $path;
  my $warnings = warnings_from sub { eval { $db->delete } };
  like $@, qr/not a coverage database/,
    "delete: instance method refuses a foreign directory";
  like $warnings, qr/found precious\.txt/,
    "delete: instance method names the unexpected file";
  ok -s File::Spec->catfile($path, "precious.txt"),
    "delete: instance method leaves the contents alone";
}

sub test_substring_names_also_refused () {
  my $path     = dir_with(qw( test_runs/ test_runs/file.txt ));
  my $warnings = warnings_from sub { eval { Devel::Cover::DB->delete($path) } };
  like $@, qr/not a coverage database/,
    "delete: refuses a directory whose entries merely contain 'runs'";
  like $warnings, qr/found test_runs/,
    "delete: names the substring-named entry";
  ok -s File::Spec->catfile($path, "test_runs", "file.txt"),
    "delete: the substring-named contents survive";
}

sub test_valid_database_is_deleted () {
  my $path = dir_with(qw( cover.15 runs/ runs/run.file digests ));
  eval { Devel::Cover::DB->delete($path) };
  is $@,             "", "delete: a valid database raises no exception";
  is entries($path), 0,  "delete: a valid database is emptied";
}

sub test_missing_directory_is_a_noop () {
  my $path = File::Spec->catdir($Tmpdir, "missing");
  my $ret  = eval { Devel::Cover::DB->delete($path) };
  is $@,     "",    "delete: a missing directory raises no exception";
  isnt $ret, undef, "delete: a missing directory returns the invocant";
}

sub test_no_db_croaks () {
  eval { Devel::Cover::DB->delete };
  like $@, qr/No db specified/, "delete: no db still croaks";
}

sub test_init_db_call_site () {
  my $path = dir_with("precious.txt");
  my @inc  = map "-I$_", qw( lib blib/lib blib/arch );
  my $cmd  = join " ", $^X, @inc, "-MDevel::Cover=-db,$path,-merge,0,-silent,1",
    "-e1", "2>&1";
  my $out = `$cmd`;
  isnt $?, 0, "delete: -merge,0 against a foreign directory aborts";
  like $out, qr/not a coverage database/, "delete: -merge,0 explains why";
  ok -s File::Spec->catfile($path, "precious.txt"),
    "delete: -merge,0 leaves the foreign directory alone";
}

sub main () {
  test_class_method_refuses_foreign_directory;
  test_instance_method_refuses_foreign_directory;
  test_substring_names_also_refused;
  test_valid_database_is_deleted;
  test_missing_directory_is_a_noop;
  test_no_db_croaks;
  test_init_db_call_site;
}

main;
done_testing;

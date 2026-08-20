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

use Test::More import => [qw( diag done_testing is like ok )];

use Devel::Cover::DB ();

## no critic (Subroutines::ProtectPrivateSubs)

{
  no feature "signatures";

  sub capture (&) {
    my ($code) = @_;
    my $err = "";
    open my $save_err, ">&", \*STDERR or die "Cannot dup STDERR: $!";
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">", \$err or die "Cannot redirect STDERR: $!";
    $code->();
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">&", $save_err or die "Cannot restore STDERR: $!";
    $err
  }
}

# Every warning in DB.pm must go through dcwarn, so a new bare warn cannot
# creep back in.  Comments are allowed to mention warn.
sub test_no_bare_warn () {
  my $file = $INC{"Devel/Cover/DB.pm"};
  ok $file, "guard: found DB.pm in %INC";
  open my $fh, "<", $file or die "Cannot open $file: $!";
  my @bare;
  while (my $l = <$fh>) {
    next if $l =~ /^\s*#/;
    push @bare, "line $.: $l" if $l =~ /\bwarn[ (\$]/;
  }
  close $fh or die "Cannot close $file: $!";
  is @bare, 0, "guard: no bare warn calls in DB.pm" or diag @bare;
}

# The five add_* methods warn when a file's structure array is shorter than
# its count array.  They take the same arguments, bar the count element shape.
sub add_cases () {
  my $db = Devel::Cover::DB->new;
  (
    ["statement",  sub { $db->add_statement({}, [], [1], {}) }],
    ["time",       sub { $db->add_time({}, [], [1], {}) }],
    ["branch",     sub { $db->add_branch({}, [], [[0, 0]], {}) }],
    ["subroutine", sub { $db->add_subroutine({}, [], [1], {}) }],
    ["condition",  sub { $db->add_condition({}, [], [[0, 0, 0]], {}) }],
  )
}

sub test_add_methods_labelled () {
  local $Devel::Cover::Silent = 0;
  for my $case (add_cases) {
    my ($criterion, $code) = @$case;
    my $err = capture { $code->() };
    is $err, "cover: Warning: ignoring extra $criterion\n",
      "add_$criterion: labelled message on STDERR";
  }
}

sub test_add_methods_silenced () {
  local $Devel::Cover::Silent = 1;
  for my $case (add_cases) {
    my ($criterion, $code) = @$case;
    my $err = capture { $code->() };
    is $err, "", "add_$criterion: silenced";
  }
}

sub test_merge_mismatch_labelled () {
  local $Devel::Cover::Silent = 0;
  my $into = ["a"];
  my $err  = capture { Devel::Cover::DB::_merge_array($into, ["b"]) };
  is $err, "cover: Warning: <a> does not match <b> - using latter value\n",
    "merge mismatch: labelled message on STDERR";
  is $into->[0], "b", "merge mismatch: latter value kept";
}

sub test_merge_mismatch_silenced () {
  local $Devel::Cover::Silent = 1;
  my $err = capture { Devel::Cover::DB::_merge_array(["a"], ["b"]) };
  is $err, "", "merge mismatch: silenced";
}

# new() validates and reads the database itself, so build quietly and let each
# test capture the call it is interested in
sub stray_file_db () {
  my $dir  = tempdir(CLEANUP => 1);
  my $file = File::Spec->catfile($dir, "stray");
  open my $fh, ">", $file or die "Cannot open $file: $!";
  close $fh or die "Cannot close $file: $!";
  local $Devel::Cover::Silent = 1;
  Devel::Cover::DB->new(db => $dir)
}

sub test_stray_file_labelled () {
  local $Devel::Cover::Silent = 0;
  my $db = stray_file_db;
  my $valid;
  my $err = capture { $valid = $db->is_valid };
  ok !$valid, "stray file: database is not valid";
  like $err, qr/^cover: Warning: found stray in /,
    "stray file: labelled message on STDERR";
}

sub test_stray_file_silenced () {
  local $Devel::Cover::Silent = 1;
  my $db  = stray_file_db;
  my $err = capture { $db->is_valid };
  is $err, "", "stray file: silenced";
}

sub unreadable_db () {
  my $dir  = tempdir(CLEANUP => 1);
  my $file = File::Spec->catfile($dir, "cover.15");
  open my $fh, ">", $file or die "Cannot open $file: $!";
  print $fh "not a coverage database" or die "Cannot write $file: $!";
  close $fh                           or die "Cannot close $file: $!";
  local $Devel::Cover::Silent = 1;
  (Devel::Cover::DB->new(db => $dir), $file)
}

sub test_unreadable_db_labelled () {
  local $Devel::Cover::Silent = 0;
  my ($db, $file) = unreadable_db;
  my $err = capture { $db->read($file) };
  like $err, qr/^cover: Warning: \S/,
    "unreadable database: labelled message with a body";
}

sub test_unreadable_db_silenced () {
  local $Devel::Cover::Silent = 1;
  my ($db, $file) = unreadable_db;
  my $err = capture { $db->read($file) };
  is $err, "", "unreadable database: silenced";
}

# The reader can return false without dying, which left the old warning with
# nothing to say
sub test_empty_db_names_the_file () {
  local $Devel::Cover::Silent = 0;
  my ($db, $file) = unreadable_db;
  my $err = capture {
    no warnings "redefine";
    local *Devel::Cover::DB::IO::read = sub { undef };
    $db->read($file);
  };
  is $err, "cover: Warning: no data in $file\n",
    "empty database: the fallback names the file";
}

sub main () {
  test_no_bare_warn;
  test_add_methods_labelled;
  test_add_methods_silenced;
  test_merge_mismatch_labelled;
  test_merge_mismatch_silenced;
  test_stray_file_labelled;
  test_stray_file_silenced;
  test_unreadable_db_labelled;
  test_unreadable_db_silenced;
  test_empty_db_names_the_file;
}

main;
done_testing;

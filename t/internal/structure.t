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

use Digest::MD5 ();
use File::Path  qw( make_path );
use File::Spec  ();
use File::Temp  qw( tempdir );
use Test::More import => [ qw( done_testing is is_deeply like ok ) ];

use Devel::Cover::DB::Structure ();

my $Tmpdir = tempdir(CLEANUP => 1);

sub write_source ($name, $content) {
  my $path = File::Spec->catfile($Tmpdir, $name);
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
  $path
}

sub md5_file ($path) {
  open my $fh, "<", $path or die "Cannot open $path: $!";
  binmode $fh;
  Digest::MD5->new->addfile($fh)->hexdigest
}

sub capture_stderr :prototype(&) ($code) {
  my $stderr = "";
  open my $save, ">&", \*STDERR or die "Cannot dup STDERR: $!";
  close STDERR or die "Cannot close STDERR: $!";
  open STDERR, ">", \$stderr or die "Cannot redirect STDERR: $!";
  $code->();
  close STDERR or die "Cannot close STDERR: $!";
  open STDERR, ">&", $save or die "Cannot restore STDERR: $!";
  $stderr
}

sub fresh_base ($label) {
  my $base = File::Spec->catdir($Tmpdir, $label);
  make_path("$base/structure");
  $base
}

sub test_new () {
  my $base = fresh_base("new");
  my $st   = Devel::Cover::DB::Structure->new(base => $base);
  ok $st, "new: returns an object";
  is ref $st, "Devel::Cover::DB::Structure", "new: correct class";
}

sub test_digest () {
  my $file     = write_source("digest.pm", "package Digest;\n1\n");
  my $expected = md5_file($file);

  my $st = Devel::Cover::DB::Structure->new;
  is $st->digest($file), $expected, "digest: matches MD5 of file";
}

sub test_digest_missing () {
  my $st     = Devel::Cover::DB::Structure->new;
  my $bogus  = File::Spec->catfile($Tmpdir, "no_such_file.pm");
  my $stderr = capture_stderr {
    my $d = $st->digest($bogus);
    ok !defined $d, "digest missing: returns undef"
  };
  like $stderr, qr/can't open/, "digest missing: warns on STDERR";
}

sub test_digest_missing_silent () {
  local $Devel::Cover::Silent = 1;
  my $st     = Devel::Cover::DB::Structure->new;
  my $bogus  = File::Spec->catfile($Tmpdir, "no_such_silent.pm");
  my $stderr = capture_stderr {
    my $d = $st->digest($bogus);
    ok !defined $d, "digest missing silent: returns undef"
  };
  is $stderr, "", "digest missing silent: no warning on STDERR";
}

sub test_set_file () {
  my $file     = write_source("setfile.pm", "package SetFile;\n1\n");
  my $expected = md5_file($file);

  my $st     = Devel::Cover::DB::Structure->new;
  my $digest = $st->set_file($file);
  is $digest,                 $expected, "set_file: returns correct digest";
  is $st->{f}{$file}{digest}, $expected, "set_file: stores digest in {f}";
  is_deeply $st->{digests}{$expected}, [$file],
    "set_file: records file in {digests}";
}

sub test_criteria () {
  my $st = Devel::Cover::DB::Structure->new;
  $st->add_criteria("statement", "branch");
  my @c = sort $st->criteria;
  is_deeply \@c, [ qw( branch statement ) ], "criteria: round-trip";
}

sub test_delete_file () {
  my $st = Devel::Cover::DB::Structure->new;
  $st->{f}{"/fake/file.pm"} = { digest => "abc", data => 1 };
  $st->delete_file("/fake/file.pm");
  ok !exists $st->{f}{"/fake/file.pm"}, "delete_file: entry removed";
}

sub test_write_read () {
  my $base   = fresh_base("write_read");
  my $file   = write_source("writeread.pm", "package WriteRead;\n1\n");
  my $digest = md5_file($file);

  # Build a structure with one file entry
  my $st = Devel::Cover::DB::Structure->new(base => $base);
  $st->add_criteria("statement");
  $st->set_file($file);
  $st->{f}{$file}{statement} = [ [ $file, 1 ] ];
  $st->write($base);

  # Read it back into a fresh object
  my $st2 = Devel::Cover::DB::Structure->new(base => $base);
  $st2->read_all;

  ok exists $st2->{f}{$file}, "write/read: file entry present";
  is $st2->{f}{$file}{digest}, $digest, "write/read: digest preserved";
  is_deeply $st2->{f}{$file}{statement}, [ [ $file, 1 ] ],
    "write/read: data preserved";
}

sub test_read_unchanged () {
  my $base   = fresh_base("read_unch");
  my $file   = write_source("unchanged.pm", "package Unchanged;\n1\n");
  my $digest = md5_file($file);

  my $st = Devel::Cover::DB::Structure->new(base => $base);
  $st->set_file($file);
  $st->write($base);

  # Read back without modifying the source file
  my $st2    = Devel::Cover::DB::Structure->new(base => $base);
  my $stderr = capture_stderr { $st2->read_all };
  ok exists $st2->{f}{$file}, "read unchanged: entry loaded";
  is $stderr, "", "read unchanged: no warning";
}

sub test_read_changed () {
  my $base = fresh_base("read_chg");
  my $file = write_source("changed.pm", "package Changed;\n1\n");

  my $st = Devel::Cover::DB::Structure->new(base => $base);
  $st->set_file($file);
  $st->write($base);

  # Modify the source file so the digest no longer matches
  write_source("changed.pm", "package Changed;\nsub x { 1 }\n1\n");

  my $st2    = Devel::Cover::DB::Structure->new(base => $base);
  my $stderr = capture_stderr { $st2->read_all };
  ok !exists $st2->{f}{$file}, "read changed: entry not loaded";
  like $stderr, qr/Deleting old coverage.*changed\.pm/,
    "read changed: warning printed";
}

sub test_read_all_empty () {
  my $base = fresh_base("read_empty");
  my $st   = Devel::Cover::DB::Structure->new(base => $base);
  $st->read_all;
  is_deeply $st->{f}, undef, "read_all empty: no entries loaded";
}

sub test_read_all_no_dir () {
  my $base = File::Spec->catdir($Tmpdir, "no_structure_dir");
  make_path($base);
  # No structure/ subdirectory
  my $st = Devel::Cover::DB::Structure->new(base => $base);
  $st->read_all;
  ok !$st->{f}, "read_all no dir: returns gracefully";
}

sub test_merge () {
  my $st1 = Devel::Cover::DB::Structure->new;
  $st1->{f}{"/a.pm"} = { digest => "aaa", statement => [ [ "/a.pm", 1 ] ] };

  my $st2 = Devel::Cover::DB::Structure->new;
  $st2->{f}{"/b.pm"} = { digest => "bbb", statement => [ [ "/b.pm", 2 ] ] };

  $st1->merge($st2);
  ok exists $st1->{f}{"/a.pm"}, "merge: original entry retained";
  ok exists $st1->{f}{"/b.pm"}, "merge: new entry added";
  is $st1->{f}{"/b.pm"}{digest}, "bbb", "merge: new entry data correct";
}

sub test_autoload_add_get () {
  my $file = write_source("autoload.pm", "package Autoload;\n1\n");
  my $st   = Devel::Cover::DB::Structure->new;
  $st->set_file($file);
  $st->add_criteria("statement", "branch", "subroutine");

  # add_statement should push data into {f}{$file}{statement}
  $st->add_statement($file, [ $file, 10 ]);
  $st->add_statement($file, [ $file, 20 ]);
  is_deeply $st->{f}{$file}{statement}, [ [ $file, 10 ], [ $file, 20 ] ],
    "autoload add: add_statement pushes entries";

  $st->add_branch($file, [ $file, 15, { text => "if block" } ]);
  is_deeply $st->{f}{$file}{branch}, [ [ $file, 15, { text => "if block" } ] ],
    "autoload add: add_branch pushes entry";

  $st->add_subroutine($file, [ $file, 5 ]);
  is_deeply $st->{f}{$file}{subroutine}, [ [ $file, 5 ] ],
    "autoload add: add_subroutine pushes entry";
}

sub test_autoload_get_by_digest () {
  my $file   = write_source("autoget.pm", "package AutoGet;\n1\n");
  my $digest = md5_file($file);
  my $st     = Devel::Cover::DB::Structure->new;
  $st->set_file($file);
  $st->add_criteria("statement");

  $st->add_statement($file, [ $file, 1 ]);

  my $got = $st->get_statement($digest);
  is_deeply $got, [ [ $file, 1 ] ],
    "autoload get: get_statement retrieves by digest";

  my $miss = $st->get_statement("nonexistent_digest");
  ok !defined $miss, "autoload get: returns undef for unknown digest";
}

sub test_autoload_get_meta () {
  my $st = Devel::Cover::DB::Structure->new;
  $st->{file}     = "/some/file.pm";
  $st->{line}     = 42;
  $st->{sub_name} = "frobnicate";

  is $st->get_file,     "/some/file.pm", "autoload get_file: returns file";
  is $st->get_line,     42,              "autoload get_line: returns line";
  is $st->get_sub_name, "frobnicate",    "autoload get_sub_name: returns name";
}

sub test_autoload_bad_method () {
  my $st = Devel::Cover::DB::Structure->new;
  my $ok = eval { $st->add_nonsense; 1 };
  ok !$ok, "autoload bad: unknown method croaks";
  like $@, qr/Undefined subroutine/, "autoload bad: correct error message";
}

sub test_add_count () {
  my $file = write_source("addcount.pm", "package AddCount;\n1\n");
  my $st   = Devel::Cover::DB::Structure->new;
  $st->set_file($file);
  $st->add_criteria("statement", "branch");

  my ($n1, $new1) = $st->add_count("statement");
  is $n1, 0, "add_count: first call returns 0";
  ok $new1, "add_count: first call is new";

  my ($n2, $new2) = $st->add_count("statement");
  is $n2, 1, "add_count: second call returns 1";
  ok $new2, "add_count: second call still new (no reuse)";

  is $st->get_count($file, "statement"), 2,
    "get_count: reflects incremented count";
}

sub test_store_counts () {
  my $file = write_source("storecounts.pm", "package StoreCounts;\n1\n");
  my $st   = Devel::Cover::DB::Structure->new;
  $st->set_file($file);
  $st->add_criteria("statement");

  # Increment the count a few times
  $st->add_count("statement");
  $st->add_count("statement");
  $st->add_count("statement");

  $st->store_counts($file);

  # store_counts should snapshot current count into the start structure
  ok exists $st->{f}{$file}{start}{-1}{__COVER__},
    "store_counts: creates __COVER__ start entry";
  is $st->{f}{$file}{start}{-1}{__COVER__}[0]{statement}, 3,
    "store_counts: records correct count";
}

sub test_reuse () {
  my $st = Devel::Cover::DB::Structure->new;

  ok !$st->reuse("/new.pm"), "reuse: false for unknown file";

  $st->{f}{"/old.pm"}{start}{-1}{__COVER__} = [ { statement => 5 } ];
  ok $st->reuse("/old.pm"), "reuse: true when __COVER__ start exists";
}

sub test_write_loose_perms () {
  my $base = fresh_base("loose");
  my $file = write_source("loose.pm", "package Loose;\n1\n");

  my $st = Devel::Cover::DB::Structure->new(base => $base, loose_perms => 1);
  $st->set_file($file);
  $st->write($base);

  my $dir_perms = (stat "$base/structure")[2] & 07777;
  is $dir_perms, 0777, "write loose_perms: structure dir is 0777";
}

sub test_write_no_digest () {
  my $base = fresh_base("no_digest");

  my $st = Devel::Cover::DB::Structure->new(base => $base);
  # Manually insert an entry with no digest
  $st->{f}{"/fake.pm"} = { data => 1 };

  my $stderr = capture_stderr { $st->write($base) };
  like $stderr, qr/Can't find digest/,
    "write no digest: warns about missing digest";

  # Verify nothing was written
  opendir my $dh, "$base/structure" or die "Cannot opendir: $!";
  my @files = grep !/^\./, readdir $dh;
  closedir $dh;
  is @files, 0, "write no digest: no file written";
}

sub test_write_no_digest_silent () {
  local $Devel::Cover::Silent = 1;
  my $base = fresh_base("no_digest_silent");

  my $st = Devel::Cover::DB::Structure->new(base => $base);
  $st->{f}{"/fake.pm"} = { data => 1 };

  my $stderr = capture_stderr { $st->write($base) };
  is $stderr, "", "write no digest silent: no warning";
}

sub main () {
  test_new;
  test_digest;
  test_digest_missing;
  test_digest_missing_silent;
  test_set_file;
  test_criteria;
  test_delete_file;
  test_write_read;
  test_read_unchanged;
  test_read_changed;
  test_read_all_empty;
  test_read_all_no_dir;
  test_merge;
  test_autoload_add_get;
  test_autoload_get_by_digest;
  test_autoload_get_meta;
  test_autoload_bad_method;
  test_add_count;
  test_store_counts;
  test_reuse;
  test_write_loose_perms;
  test_write_no_digest;
  test_write_no_digest_silent;
  done_testing;
}

main;

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
use Test::More import => [qw( done_testing is is_deeply like ok pass )];

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

{
  no feature "signatures";

  sub capture_stderr (&) {
    my ($code) = @_;
    my $stderr = "";
    open my $save, ">&", \*STDERR or die "Cannot dup STDERR: $!";
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">", \$stderr or die "Cannot redirect STDERR: $!";
    $code->();
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">&", $save or die "Cannot restore STDERR: $!";
    $stderr
  }
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
  is_deeply \@c, [qw( branch statement )], "criteria: round-trip";
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

sub test_read_changed_silent () {
  local $Devel::Cover::Silent = 1;
  my $base = fresh_base("read_chg_s");
  my $file = write_source("changed_s.pm", "package ChangedS;\n1\n");

  my $st = Devel::Cover::DB::Structure->new(base => $base);
  $st->set_file($file);
  $st->write($base);

  # Modify the source file so the digest no longer matches
  write_source("changed_s.pm", "package ChangedS;\nsub x { 1 }\n1\n");

  my $st2    = Devel::Cover::DB::Structure->new(base => $base);
  my $stderr = capture_stderr { $st2->read_all };
  ok !exists $st2->{f}{$file}, "read changed silent: entry not loaded";
  is $stderr, "", "read changed silent: no warning";
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

sub test_write_creates_structure_dir () {
  my $base = File::Spec->catdir($Tmpdir, "write_mkdir");
  make_path($base);
  # Don't pre-create structure/ - let write() do it
  my $file = write_source("mkdir.pm", "package MkDir;\n1\n");

  my $st = Devel::Cover::DB::Structure->new(base => $base);
  $st->set_file($file);
  $st->write($base);

  ok -d "$base/structure", "write mkdir: creates structure dir";
}

sub test_write_rename_failure () {
  my $base   = fresh_base("rename_fail");
  my $file   = write_source("renamefail.pm", "package RenameFail;\n1\n");
  my $digest = md5_file($file);

  my $st = Devel::Cover::DB::Structure->new(base => $base);
  $st->set_file($file);

  # Pre-create target as a directory so rename fails
  mkdir "$base/structure/$digest"
    or die "Cannot mkdir $base/structure/$digest: $!";

  my $stderr = capture_stderr { $st->write($base) };
  rmdir "$base/structure/$digest";

  like $stderr, qr/Can't rename/, "write rename fail: warns on STDERR";
}

sub test_write_rename_failure_silent () {
  local $Devel::Cover::Silent = 1;
  my $base   = fresh_base("rename_fail_s");
  my $file   = write_source("renamefails.pm", "package RenameFailS;\n1\n");
  my $digest = md5_file($file);

  my $st = Devel::Cover::DB::Structure->new(base => $base);

  $st->set_file($file);

  mkdir "$base/structure/$digest"
    or die "Cannot mkdir $base/structure/$digest: $!";

  my $stderr = capture_stderr { $st->write($base) };
  rmdir "$base/structure/$digest";

  is $stderr, "", "write rename fail silent: no warning";
}

sub test_autoload_get_time () {
  my $file   = write_source("time.pm", "package Time;\n1\n");
  my $digest = md5_file($file);
  my $st     = Devel::Cover::DB::Structure->new;
  $st->set_file($file);

  # time criterion maps to statement internally
  $st->{f}{$file}{statement} = [ [ $file, 1 ] ];

  my $got = $st->get_time($digest);
  is_deeply $got, [ [ $file, 1 ] ], "autoload get_time: maps to statement data";
}

sub test_set_file_missing () {
  my $st    = Devel::Cover::DB::Structure->new;
  my $bogus = File::Spec->catfile($Tmpdir, "no_such_setfile.pm");

  my $stderr = capture_stderr {
    my $digest = $st->set_file($bogus);
    ok !defined $digest, "set_file missing: returns undef"
  };
  ok !exists $st->{f}{$bogus}{digest}, "set_file missing: no digest stored";
}

sub test_add_count_no_file () {
  my $st = Devel::Cover::DB::Structure->new;
  $st->add_criteria("statement");
  # $self->{file} is undef - should return early
  my @result = $st->add_count("statement");
  is @result, 0, "add_count no file: returns empty";
}

sub test_set_subroutine_new () {
  my $file = write_source("setsub_new.pm", "package SetSubNew;\n1\n");
  my $st   = Devel::Cover::DB::Structure->new;
  $st->set_file($file);
  $st->add_criteria("statement");

  # Increment count so get_count returns something
  $st->add_count("statement");
  $st->add_count("statement");

  $st->set_subroutine("mysub", $file, 10, 0);

  is $st->{sub_name}, "mysub", "set_sub new: sets sub_name";
  is $st->{file},     $file,   "set_sub new: sets file";
  is $st->{line},     10,      "set_sub new: sets line";
  ok exists $st->{f}{$file}{start}{10}{mysub}[0]{statement},
    "set_sub new: creates start entry";
  is $st->{f}{$file}{start}{10}{mysub}[0]{statement}, 2,
    "set_sub new: start entry has correct count";
}

sub test_set_subroutine_reuse_existing () {
  my $file = write_source("setsub_reuse.pm", "package SetSubReuse;\n1\n");
  my $st   = Devel::Cover::DB::Structure->new;
  $st->set_file($file);
  $st->add_criteria("statement");

  # Set up a reusable structure with __COVER__ and an existing sub
  $st->{f}{$file}{start}{-1}{__COVER__} = [ { statement => 0 } ];
  $st->{f}{$file}{start}{10}{oldsub}    = [ { statement => 5 } ];

  $st->set_subroutine("oldsub", $file, 10, 0);

  is $st->{count}{statement}{$file}, 5,
    "set_sub reuse existing: restores count from start";
  ok !$st->{additional}, "set_sub reuse existing: additional flag is false";
}

sub test_set_subroutine_reuse_additional_first () {
  my $file = write_source("setsub_add1.pm", "package SetSubAdd1;\n1\n");
  my $st   = Devel::Cover::DB::Structure->new;
  $st->set_file($file);
  $st->add_criteria("statement");

  # Set up reusable structure but without the sub we'll request
  $st->{f}{$file}{start}{-1}{__COVER__} = [ { statement => 10 } ];

  $st->set_subroutine("newsub", $file, 20, 0);

  ok $st->{additional},
    "set_sub reuse additional first: additional flag is true";
  is $st->{count}{statement}{$file}, 10,
    "set_sub reuse additional first: count from __COVER__";
}

sub test_set_subroutine_reuse_additional_repeat () {
  my $file = write_source("setsub_add2.pm", "package SetSubAdd2;\n1\n");
  my $st   = Devel::Cover::DB::Structure->new;
  $st->set_file($file);
  $st->add_criteria("statement");

  # Set up reusable structure without the sub
  $st->{f}{$file}{start}{-1}{__COVER__} = [ { statement => 10 } ];
  # Simulate that we've already seen an additional sub in this file
  $st->{additional_count}{statement}{$file} = 1;

  $st->set_subroutine("another", $file, 30, 0);

  ok $st->{additional},
    "set_sub reuse additional repeat: additional flag is true";
  # Count should come from add_count, not from __COVER__
  ok defined $st->{f}{$file}{start}{30}{another}[0]{statement},
    "set_sub reuse additional repeat: start entry created";
}

sub test_add_count_with_additional () {
  my $file = write_source("addcount_add.pm", "package AddCountAdd;\n1\n");
  my $st   = Devel::Cover::DB::Structure->new;
  $st->set_file($file);
  $st->add_criteria("statement");
  $st->{additional} = 1;

  my ($n, $new) = $st->add_count("statement");
  is $n, 0, "add_count additional: returns count";
  is $st->{additional_count}{statement}{$file}, 1,
    "add_count additional: increments additional_count";
}

sub test_add_count_reuse_not_additional () {
  my $file = write_source("addcount_reuse.pm", "package AddCountReuse;\n1\n");
  my $st   = Devel::Cover::DB::Structure->new;
  $st->set_file($file);
  $st->add_criteria("statement");

  # Set up reuse so the || branch in add_count is tested
  $st->{f}{$file}{start}{-1}{__COVER__} = [ { statement => 0 } ];
  $st->{additional} = 0;

  my ($n, $new) = $st->add_count("statement");
  ok !$new, "add_count reuse not additional: new is false";
}

sub test_read_corrupt () {
  my $base = fresh_base("read_corrupt");

  # Write a corrupt file into the structure directory
  my $corrupt = "$base/structure/deadbeef0123456789abcdef01234567";
  open my $fh, ">", $corrupt or die "Cannot write $corrupt: $!";
  print $fh "this is not valid serialised data";
  close $fh or die "Cannot close $corrupt: $!";

  my $st = Devel::Cover::DB::Structure->new(base => $base);
  my $ok = eval { $st->read_all; 1 };
  ok !$ok, "read corrupt: dies on corrupt data";
}

sub test_read_source_deleted () {
  my $base = fresh_base("read_deleted");
  my $file = write_source("deleted.pm", "package Deleted;\n1\n");

  my $st = Devel::Cover::DB::Structure->new(base => $base);
  $st->set_file($file);
  $st->write($base);

  # Remove the source file so digest returns undef
  unlink $file or die "Cannot unlink $file: $!";

  local $Devel::Cover::Silent = 1;
  my $st2 = Devel::Cover::DB::Structure->new(base => $base);
  $st2->read_all;

  # The !$d branch: entry not loaded, but also not deleted
  ok !exists $st2->{f}{$file}, "read source deleted: entry not loaded";
}

sub test_destroy () {
  my $st = Devel::Cover::DB::Structure->new;
  $st->DESTROY;
  pass "DESTROY: can be called explicitly";
}

sub test_digest_ignored_file () {
  my $st     = Devel::Cover::DB::Structure->new;
  my $ignore = "/some/lib/Storable.pm";
  my $stderr = capture_stderr {
    my $d = $st->digest($ignore);
    ok !defined $d, "digest ignored: returns undef"
  };
  is $stderr, "", "digest ignored: no warning for ignored file";
}

sub test_write_no_digest_self_cover () {
  local $Devel::Cover::Self_cover = 1;
  my $base = fresh_base("no_digest_self");

  my $st = Devel::Cover::DB::Structure->new(base => $base);
  $st->{f}{"/lib/Devel/Cover/Foo.pm"} = { data => 1 };

  my $stderr = capture_stderr { $st->write($base) };
  is $stderr, "", "write no digest self_cover: no warning for DC module";
}

sub test_write_no_digest_ignored () {
  my $base = fresh_base("no_digest_ign");

  my $st = Devel::Cover::DB::Structure->new(base => $base);
  $st->{f}{"/some/lib/POSIX.pm"} = { data => 1 };

  my $stderr = capture_stderr { $st->write($base) };
  is $stderr, "", "write no digest ignored: no warning for ignored file";
}

sub test_write_no_digest_self_cover_no_match () {
  local $Devel::Cover::Self_cover = 1;
  my $base = fresh_base("no_digest_self_nm");

  my $st = Devel::Cover::DB::Structure->new(base => $base);
  # Path does not match /Devel/Cover[./] so the Self_cover guard
  # doesn't suppress the warning
  $st->{f}{"/lib/Some/Other.pm"} = { data => 1 };

  my $stderr = capture_stderr { $st->write($base) };
  like $stderr, qr/Can't find digest/,
    "write no digest self_cover no match: warns";
}

sub test_autoload_no_criterion () {
  my $st = Devel::Cover::DB::Structure->new;
  # "get_" has an empty criterion, so the regex captures undef
  my $ok = eval { $st->get_; 1 };
  ok !$ok, "autoload no criterion: croaks";
  like $@, qr/Undefined subroutine/, "autoload no criterion: correct error";
}

sub test_digest_dash_e () {
  my $st     = Devel::Cover::DB::Structure->new;
  my $stderr = capture_stderr {
    my $d = $st->digest("-e");
    ok !defined $d, "digest -e: returns undef"
  };
  is $stderr, "", "digest -e: suppresses warning for -e";
}

sub test_set_complexity () {
  my $file = write_source("setcc.pm", "package SetCC;\nsub mysub {}\n1\n");
  my $st   = Devel::Cover::DB::Structure->new;
  $st->set_file($file);

  my $sub_id = [ $file, 10, "mysub", 0 ];
  $st->set_complexity($sub_id, 5);

  is $st->{f}{$file}{complexity}{10}{mysub}[0], 5,
    "set_complexity: stores CC at correct key";
}

sub test_set_complexity_multiple_subs () {
  my $file
    = write_source("setcc2.pm", "package SetCC2;\nsub a {}\nsub b {}\n1\n");
  my $st = Devel::Cover::DB::Structure->new;
  $st->set_file($file);

  $st->set_complexity([ $file, 10, "sub_a", 0 ], 3);
  $st->set_complexity([ $file, 20, "sub_b", 0 ], 7);

  is $st->{f}{$file}{complexity}{10}{sub_a}[0], 3,
    "set_complexity multi: first sub has correct CC";
  is $st->{f}{$file}{complexity}{20}{sub_b}[0], 7,
    "set_complexity multi: second sub has correct CC";
}

sub test_complexity_write_read () {
  my $base = fresh_base("cc_write_read");
  my $file = write_source("ccwr.pm", "package CCWR;\nsub f {}\n1\n");

  my $st = Devel::Cover::DB::Structure->new(base => $base);
  $st->set_file($file);
  $st->set_complexity([ $file, 5, "f", 0 ], 4);
  $st->write($base);

  my $st2 = Devel::Cover::DB::Structure->new(base => $base);
  $st2->read_all;

  is $st2->{f}{$file}{complexity}{5}{f}[0], 4,
    "complexity write/read: survives round-trip";
}

sub test_get_complexity () {
  my $file   = write_source("getcc.pm", "package GetCC;\nsub g {}\n1\n");
  my $digest = md5_file($file);
  my $st     = Devel::Cover::DB::Structure->new;
  $st->set_file($file);
  $st->set_complexity([ $file, 8, "g", 0 ], 6);

  my $got = $st->get_complexity($digest);
  is_deeply $got, { 8 => { g => [6] } }, "get_complexity: retrieves by digest";

  my $miss = $st->get_complexity("nonexistent_digest");
  ok !defined $miss, "get_complexity: returns undef for unknown digest";
}

sub test_set_end_line () {
  my $file = write_source("setend.pm", "package SetEnd;\nsub f {}\n1\n");
  my $st   = Devel::Cover::DB::Structure->new;
  $st->set_file($file);

  my $sub_id = [ $file, 10, "f", 0 ];
  $st->set_end_line($sub_id, 25);

  is $st->{f}{$file}{end_line}{10}{f}[0], 25,
    "set_end_line: stores end line at correct key";
}

sub test_get_end_lines () {
  my $file   = write_source("getend.pm", "package GetEnd;\nsub g {}\n1\n");
  my $digest = md5_file($file);
  my $st     = Devel::Cover::DB::Structure->new;
  $st->set_file($file);
  $st->set_end_line([ $file, 8, "g", 0 ], 20);

  my $got = $st->get_end_lines($digest);
  is_deeply $got, { 8 => { g => [20] } }, "get_end_lines: retrieves by digest";

  my $miss = $st->get_end_lines("nonexistent_digest");
  ok !defined $miss, "get_end_lines: returns undef for unknown digest";
}

sub test_end_line_write_read () {
  my $base = fresh_base("end_write_read");
  my $file = write_source("endwr.pm", "package EndWR;\nsub f {}\n1\n");

  my $st = Devel::Cover::DB::Structure->new(base => $base);
  $st->set_file($file);
  $st->set_end_line([ $file, 5, "f", 0 ], 15);
  $st->write($base);

  my $st2 = Devel::Cover::DB::Structure->new(base => $base);
  $st2->read_all;

  is $st2->{f}{$file}{end_line}{5}{f}[0], 15,
    "end_line write/read: survives round-trip";
}

sub test_set_subroutine_returns_sub_id () {
  my $file = write_source("subid.pm", "package SubId;\nsub h {}\n1\n");
  my $st   = Devel::Cover::DB::Structure->new;
  $st->set_file($file);
  $st->add_criteria("statement");
  $st->add_count("statement");

  my $sub_id = $st->set_subroutine("h", $file, 15, 0);
  is_deeply $sub_id, [ $file, 15, "h", 0 ], "set_subroutine: returns sub_id";

  $st->set_complexity($sub_id, 9);
  is $st->{f}{$file}{complexity}{15}{h}[0], 9,
    "set_subroutine + set_complexity: end-to-end via sub_id";
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
  test_read_changed_silent;
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
  test_write_creates_structure_dir;
  test_write_rename_failure;
  test_write_rename_failure_silent;
  test_autoload_get_time;
  test_set_file_missing;
  test_add_count_no_file;
  test_set_subroutine_new;
  test_set_subroutine_reuse_existing;
  test_set_subroutine_reuse_additional_first;
  test_set_subroutine_reuse_additional_repeat;
  test_add_count_with_additional;
  test_add_count_reuse_not_additional;
  test_read_corrupt;
  test_read_source_deleted;
  test_destroy;
  test_digest_ignored_file;
  test_write_no_digest_self_cover;
  test_write_no_digest_ignored;
  test_write_no_digest_self_cover_no_match;
  test_autoload_no_criterion;
  test_digest_dash_e;
  test_set_complexity;
  test_set_complexity_multiple_subs;
  test_complexity_write_read;
  test_get_complexity;
  test_set_end_line;
  test_get_end_lines;
  test_end_line_write_read;
  test_set_subroutine_returns_sub_id;
}

main;
done_testing;

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
use Test::More import => [qw( done_testing is like ok )];

use Devel::Cover::Annotation::Git;

my $Dir = tempdir(CLEANUP => 1);

$Devel::Cover::Silent = 1;

sub write_helper () {
  # A plain heredoc, not <<~, because indented heredocs need 5.26
  my $helper = "$Dir/blame.pl";
  open my $fh, ">", $helper or die "Can't open $helper: $!";
  print $fh <<'PERL';
my $sha = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
print "$sha 1 1 1\n";
print "author A U Thor\n";
print "author-time 1234567890\n";
print "\tmy code line\n";
PERL
  close $fh or die "Can't close $helper: $!";
  $helper
}

sub annotator_for ($helper) {
  Devel::Cover::Annotation::Git->new(command => qq("$^X" "$helper" [[file]]))
}

sub capture ($git, $file) {
  my ($stdout, $stderr) = ("", "");
  {
    local *STDOUT;
    local *STDERR;
    open STDOUT, ">", \$stdout or die "Can't redirect STDOUT: $!";
    open STDERR, ">", \$stderr or die "Can't redirect STDERR: $!";
    $git->get_annotations($file);
  }
  ($stdout, $stderr)
}

sub quiet_annotations ($git, $file) {
  my ($stdout, $stderr) = capture($git, $file);
  is $stdout . $stderr, "", "annotating $file prints nothing";
}

sub test_version_column () {
  my $git  = annotator_for(write_helper);
  my $file = "lib/Foo.pm";

  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_ };
  quiet_annotations($git, $file);

  is $git->text($file, 1, 0), "deadbeef", "version column holds short SHA";
  is $git->text($file, 1, 1), "A U Thor", "author column";
  is "@warnings", "", "no warnings while parsing blame output";
}

sub write_args_helper () {
  my $helper = "$Dir/args.pl";
  open my $fh, ">", $helper or die "Can't open $helper: $!";
  print $fh <<'PERL';
my $args = join "|", @ARGV;
print "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 1 1 1\n";
print "author $args\n";
print "author-time 1234567890\n";
print "\tmy code line\n";
PERL
  close $fh or die "Can't close $helper: $!";
  $helper
}

sub test_path_with_spaces () {
  my $git  = annotator_for(write_args_helper);
  my $file = "dir with space/file.pm";
  quiet_annotations($git, $file);
  is $git->text($file, 1, 1), $file, "path with spaces arrives as one argument";
}

sub test_path_with_metacharacters () {
  my $git   = annotator_for(write_args_helper);
  my $probe = "$Dir/pwned";
  my $file  = "x.pm; touch $probe";
  quiet_annotations($git, $file);
  is $git->text($file, 1, 1), $file,
    "metacharacters arrive literally in one argument";
  ok !-e $probe, "no shell command injected via the file name";
}

sub write_repeat_helper () {
  my $helper = "$Dir/repeat.pl";
  open my $fh, ">", $helper or die "Can't open $helper: $!";
  print $fh <<'PERL';
my $a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
my $b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
print "$a 1 1 1\n";
print "author Ann Author\n";
print "author-time 1000000000\n";
print "\tline one\n";
print "$b 2 2 1\n";
print "author Bob Blame\n";
print "author-time 1100000000\n";
print "\tline two\n";
print "$a 3 3 1\n";
print "\tline three\n";
PERL
  close $fh or die "Can't close $helper: $!";
  $helper
}

sub test_repeated_commit () {
  my $git  = annotator_for(write_repeat_helper);
  my $file = "lib/Foo.pm";
  quiet_annotations($git, $file);

  is $git->text($file, 3, 0), "aaaaaaaa", "repeated commit keeps its sha";
  is $git->text($file, 3, 1), "Ann Author",
    "repeated commit keeps its own author";
  is $git->text($file, 3, 2), $git->text($file, 1, 2),
    "repeated commit keeps its own date";
}

sub capture_annotation ($file) {
  capture(annotator_for(write_helper), $file)
}

sub test_status_line_routing () {
  local $Devel::Cover::Silent = 0;
  my ($stdout, $stderr) = capture_annotation("lib/Foo.pm");
  is $stdout, "", "the status line stays off STDOUT";
  like $stderr, qr|^cover: Getting git annotation information for lib/Foo|m,
    "the status line goes to STDERR";
}

sub test_status_line_honours_silent () {
  local $Devel::Cover::Silent = 1;
  my ($stdout, $stderr) = capture_annotation("lib/Bar.pm");
  is $stdout . $stderr, "", "-silent suppresses the status line";
}

sub main () {
  test_version_column;
  test_path_with_spaces;
  test_path_with_metacharacters;
  test_repeated_commit;
  test_status_line_routing;
  test_status_line_honours_silent;
}

main;
done_testing;

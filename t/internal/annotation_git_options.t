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
use Test::More import => [qw( done_testing is ok )];

use Devel::Cover::Annotation::Git;

my $Dir = tempdir(CLEANUP => 1);

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

sub annotator_with_options (@argv) {
  my $git = Devel::Cover::Annotation::Git->new(
    command => qq("$^X" "@{[ write_helper ]}" [[file]]));
  local @ARGV = @argv;
  $git->get_options({});
  is "@ARGV", "", "options consumed: @argv";
  $git
}

sub test_noauthor () {
  my $git = annotator_with_options("-noauthor");
  is $git->count,     2,         "-noauthor leaves two columns";
  is $git->header(0), "version", "first column is version";
  is $git->header(1), "date",    "second column is date";
  is $git->width(1),  24,        "date column keeps its width";
}

sub test_nosha () {
  my $git = annotator_with_options("-nosha");
  is $git->count,     2,        "-nosha leaves two columns";
  is $git->header(0), "author", "first column is author";
  is $git->header(1), "date",   "second column is date";
  is $git->width(0),  16,       "author column keeps its width";
  is $git->width(1),  24,       "date column keeps its width";
}

sub test_only_version () {
  my $git = annotator_with_options("-noauthor", "-nodate");
  is $git->count,     1,         "one column left";
  is $git->header(0), "version", "the column is version";
  is $git->width(0),  8,         "version column keeps its width";
  my $file = "lib/Foo.pm";
  is $git->text($file, 1, 0), "deadbeef", "text returns the short sha";
}

sub test_all_off () {
  my $git = annotator_with_options("-nosha", "-noauthor", "-nodate");
  is $git->count, 0, "no columns left";
}

sub test_defaults () {
  my $git = annotator_with_options();
  is $git->count,     3,         "all three columns by default";
  is $git->header(0), "version", "version first";
  is $git->header(1), "author",  "author second";
  is $git->header(2), "date",    "date third";
  is $git->width(0),  8,         "version width";
  is $git->width(1),  16,        "author width";
  is $git->width(2),  24,        "date width";
}

sub test_new_without_get_options () {
  my $git = Devel::Cover::Annotation::Git->new;
  is $git->count, 3, "an object built without get_options has three columns";
}

sub main () {
  test_noauthor;
  test_nosha;
  test_only_version;
  test_all_off;
  test_defaults;
  test_new_without_get_options;
}

main;
done_testing;

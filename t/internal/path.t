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

use Test::More import => [ qw( done_testing is is_deeply ) ];

use Devel::Cover::Path qw( common_prefix );

sub test_empty_list () {
  my ($prefix, $short) = common_prefix();
  is $prefix, "", "empty list: prefix";
  is_deeply $short, {}, "empty list: short map";
}

sub test_single_file () {
  my ($prefix, $short) = common_prefix("/a/b/c/foo.pm");
  is $prefix, "", "single file: prefix";
  is_deeply $short, { "/a/b/c/foo.pm" => "/a/b/c/foo.pm" },
    "single file: short map";
}

sub test_same_directory () {
  my ($prefix, $short) = common_prefix("/a/b/foo.pm", "/a/b/bar.pm");
  is $prefix, "/a/b/", "same directory: prefix";
  is_deeply $short, { "/a/b/foo.pm" => "foo.pm", "/a/b/bar.pm" => "bar.pm" },
    "same directory: short map";
}

sub test_different_depths () {
  my ($prefix, $short) = common_prefix("/a/b/c/foo.pm", "/a/b/bar.pm");
  is $prefix, "/a/b/", "different depths: prefix";
  is_deeply $short,
    { "/a/b/c/foo.pm" => "c/foo.pm", "/a/b/bar.pm" => "bar.pm" },
    "different depths: short map";
}

sub test_identical_files () {
  my ($prefix, $short) = common_prefix("/a/b/foo.pm", "/a/b/foo.pm");
  is $prefix, "/a/b/", "identical files: prefix";
  is_deeply $short, { "/a/b/foo.pm" => "foo.pm" }, "identical files: short map";
}

sub test_bare_slash_prefix () {
  my ($prefix, $short) = common_prefix("/a/foo.pm", "/b/bar.pm");
  is $prefix, "", "bare / prefix: prefix";
  is_deeply $short, { "/a/foo.pm" => "/a/foo.pm", "/b/bar.pm" => "/b/bar.pm" },
    "bare / prefix: short map";
}

sub test_relative_paths () {
  my ($prefix, $short) = common_prefix("lib/Foo.pm", "lib/Bar.pm");
  is $prefix, "lib/", "relative paths: prefix";
  is_deeply $short, { "lib/Foo.pm" => "Foo.pm", "lib/Bar.pm" => "Bar.pm" },
    "relative paths: short map";
}

sub test_total_in_list () {
  my ($prefix, $short) = common_prefix("/a/b/foo.pm", "/a/b/bar.pm", "Total");
  is $prefix, "/a/b/", "Total in list: prefix";
  is_deeply $short,
    { "/a/b/foo.pm" => "foo.pm", "/a/b/bar.pm" => "bar.pm", Total => "Total" },
    "Total in list: short map";
}

sub test_total_only () {
  my ($prefix, $short) = common_prefix("Total");
  is $prefix, "", "Total only: prefix";
  is_deeply $short, { Total => "Total" }, "Total only: short map";
}

sub test_three_levels_shared () {
  my ($prefix, $short) = common_prefix("/a/b/c/d/foo.pm", "/a/b/c/e/bar.pm");
  is $prefix, "/a/b/c/", "three levels shared: prefix";
  is_deeply $short,
    { "/a/b/c/d/foo.pm" => "d/foo.pm", "/a/b/c/e/bar.pm" => "e/bar.pm" },
    "three levels shared: short map";
}

sub test_mixed_depths () {
  my ($prefix, $short) = common_prefix(
    "/a/b/c/Foo.pm",         ##
    "/a/b/c/Bar.pm",         ##
    "/a/b/c/Baz.pm",         ##
    "/a/b/c/d/e/Deep.pm",    ##
    "/a/b/c/d/e/Deeper.pm",  ##
  );
  is $prefix, "/a/b/c/", "mixed depths: prefix";
  is_deeply $short, {
      "/a/b/c/Foo.pm"        => "Foo.pm",
      "/a/b/c/Bar.pm"        => "Bar.pm",
      "/a/b/c/Baz.pm"        => "Baz.pm",
      "/a/b/c/d/e/Deep.pm"   => "d/e/Deep.pm",
      "/a/b/c/d/e/Deeper.pm" => "d/e/Deeper.pm",
    },
    "mixed depths: short map";
}

sub test_no_shared_components () {
  my ($prefix, $short) = common_prefix("src/Foo.pm", "lib/Bar.pm");
  is $prefix, "", "no shared components: prefix";
  is_deeply $short,
    { "src/Foo.pm" => "src/Foo.pm", "lib/Bar.pm" => "lib/Bar.pm" },
    "no shared components: short map";
}

sub main () {
  test_empty_list;
  test_single_file;
  test_same_directory;
  test_different_depths;
  test_identical_files;
  test_bare_slash_prefix;
  test_relative_paths;
  test_total_in_list;
  test_total_only;
  test_three_levels_shared;
  test_mixed_depths;
  test_no_shared_components;
  done_testing;
}

main;

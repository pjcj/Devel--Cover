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

use Test::More import => [qw( done_testing is ok )];

# queue builds the path it hands to dc from the CPAN uploads feed, so it may
# contain spaces or other characters a shell would split.  The path must reach
# dc as a single argument, and anything that is not a real author path must be
# refused.  A real author path has four components and its first two
# directories repeat the leading characters of the author id.

my $Queue = "$FindBin::Bin/../../bin/queue";

sub source () {
  open my $fh, "<", $Queue or die "Can't read $Queue: $!";
  my $src = do { local $/; <$fh> };
  close $fh or die "Can't close $Queue: $!";
  $src
}

# The guard in bin/queue, extracted so the pattern is exercised directly.
# Kept in step with the script by the source check below.
sub accepts ($path) {
  $path =~ m{\A([A-Z])/\1([A-Z0-9])/\1\2[A-Z0-9]*/[A-Za-z0-9][\w.+-]*\z} ? 1 : 0
}

sub main () {
  my $src = source;

  like_command($src);

  for my $path (
    "P/PJ/PJCJ/Shell-Source-0.01.tar.gz",
    "A/AB/ABC/Foo-Bar-1.23.tar.bz2",
    "M/MS/MSCHWERN/Test-Simple-1.302199.tar.gz",
    "J/JV/JV/PostScript-Font-1.09.tar.gz",
    "P/PE/PERLANCAR/App-cpanm-0.01.tar.gz",
    "L/LD/LDS/GD-2.53.tar.gz",
    "S/SA/SAMPLE/Foo-C++-1.0.tar.gz",
  ) {
    is accepts($path), 1, "genuine author path is accepted: $path";
  }

  for my $path (
    "P/PJ/PJCJ/x.tar.gz; touch MARKER",
    "P/PJ/PJCJ/`id`.tar.gz",
    'P/PJ/PJCJ/$(id).tar.gz',
    "P/PJ/PJCJ/x|nc host 1234",
    "P/PJ/PJCJ/x.tar.gz && id",
    "-rf /",
    "P/PJ/../../../etc/passwd",
    "P/PJ/PJCJ/x .tar.gz",
  ) {
    is accepts($path), 0, "path with metacharacters is refused: $path";
  }

  for my $path (
    "P/PX/PJCJ/Foo-1.0.tar.gz", "X/PJ/PJCJ/Foo-1.0.tar.gz",
    "p/pj/pjcj/Foo-1.0.tar.gz", "PJCJ/Foo-1.0.tar.gz",
    "M/MS/MSCHWERN/sub/Test-Simple-1.0.tar.gz",
  ) {
    is accepts($path), 0, "malformed author path is refused: $path";
  }

  done_testing;
}

sub like_command ($src) {
  ok $src =~ /\bsystem \@command\b/,
    "queue runs dc through list-form system, so no shell parses the path";
  ok $src !~ /\bsystem \$command\b/,
    "queue does not run dc through a single-string system";
  ok $src =~ m{\Q\A([A-Z])/\1([A-Z0-9])/\1\2[A-Z0-9]*/[A-Za-z0-9][\w.+-]*\z\E},
    "queue guards the path with the pattern this test exercises";
}

main;

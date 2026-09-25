#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use File::Find   qw( find );
use File::Spec   ();
use FindBin      ();
use Pod::Checker ();

use Test::More import => [qw( diag done_testing is )];

my $Root = File::Spec->catdir($FindBin::Bin, "..", "..");

sub pod_files () {
  my @files;
  find(
    {
      wanted   => sub { push @files, $_ if -f && /\.(?:pm|pod)$/ },
      no_chdir => 1,
    },
    File::Spec->catdir($Root, "lib"),
  );
  push @files, glob File::Spec->catfile($Root, "bin", "*");
  sort @files
}

sub check_pod ($file) {
  my $out = "";
  open my $fh, ">", \$out or die "Cannot open string handle: $!";
  my $checker = Pod::Checker->new(-warnings => 1);
  $checker->parse_from_file($file, $fh);
  close $fh or die "Cannot close string handle: $!";
  my $errors = $checker->num_errors;
  $errors = 0 if $errors < 0;  # no POD at all is not a fault
  my $problems = $errors + $checker->num_warnings;
  my $name     = File::Spec->abs2rel($file, $Root);
  is $problems, 0, "$name has clean POD" or diag $out;
}

sub main () { check_pod($_) for pod_files }

main;
done_testing;

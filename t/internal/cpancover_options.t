#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin    ();
use File::Spec ();

use Test::More import => [qw( done_testing is_deeply )];

sub read_script () {
  my $script
    = File::Spec->catfile($FindBin::Bin, "..", "..", "bin", "cpancover");
  open my $fh, "<", $script or die "Can't open $script: $!";
  my $src = do { local $/; <$fh> };
  close $fh or die "Can't close $script: $!";
  $src
}

# Long option names accepted by the GetOptions spec (drop =s/=i/! and split
# aliases, then ignore single-character short forms like h, i, v).
sub spec_options ($src) {
  my ($spec) = $src =~ /GetOptions\(\s*\$Options,\s*qw\(\s*(.*?)\)\s*\)/s;
  my %real;
  for my $tok (split " ", $spec) {
    $tok =~ s/[=:].*//;
    $tok =~ s/!$//;
    $real{$_} = 1 for grep length > 1, split /\|/, $tok;
  }
  \%real
}

# Long option names documented in the POD OPTIONS section.
sub documented_options ($src) {
  my ($opts_pod) = $src =~ /=head1 OPTIONS\b(.*?)=head1/s;
  +{ map { $_ => 1 } $opts_pod =~ /--(\w+)/g }
}

sub test_options () {
  my $src = read_script;
  is_deeply [sort keys documented_options($src)->%*],
    [sort keys spec_options($src)->%*],
    "documented options match the GetOptions spec";
}

test_options;

done_testing;

#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.42.0;

use Test2::V0 qw( diag done_testing is like ok skip_all );

use CPAN::Distroprefs ();

skip_all "YAML required" unless eval { require YAML; 1 };

my $Dir = "docker/devel-cover-base/prefs";

sub prefs_files () {
  opendir my $dh, $Dir or die "Can't open $Dir: $!";
  my @files = sort grep !/^\./, readdir $dh;
  closedir $dh;
  @files
}

sub load_prefs () {
  my @prefs;
  my $finder = CPAN::Distroprefs->find($Dir, { yml => "YAML" });
  while (my $result = $finder->next) {
    ok $result->is_success, $result->file . " loads" or diag $result->as_string;
    push @prefs, $result->prefs->@* if $result->is_success;
  }
  @prefs
}

# The base image installs YAML, and CPAN.pm then reads only .yml prefs, so a
# file with any other extension is ignored without a word.
my @Files = prefs_files;
ok @Files, "prefs directory has files";
like $_, qr/\.yml\z/, "$_ has the extension CPAN reads" for @Files;

my @Prefs = load_prefs;
for my $pref (@Prefs) {
  my $data = $pref->data;
  ok $pref->has_match("distribution"), "$data->{comment}: matches distribution";
  is $data->{disabled}, 1, "$data->{comment}: disables the build";
}

sub refusals ($id) { scalar grep $_->matches({ distribution => $id }), @Prefs }

my @Refused = qw(
  GOZER/mod_perl-1.31.tar.gz
  GOZER/mod_perl-1.29.tar.gz
);
my @Allowed = qw(
  ETHER/mod_perl-2.0.13.tar.gz
  PJCJ/Devel-Cover-1.50.tar.gz
);

is refusals($_), 1, "$_ is refused by one prefs file" for @Refused;
is refusals($_), 0, "$_ is not refused"               for @Allowed;

done_testing;

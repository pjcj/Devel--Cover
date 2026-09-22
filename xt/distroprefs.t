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
  KWILLIAMS/Apache-Filter-1.024.tar.gz
  KWILLIAMS/Apache-SSI-2.19.tar.gz
  KWILLIAMS/Apache-Compress-1.005.tar.gz
  MAUNDER/Apache-AppCluster-0.02.tar.gz
  AMURREN/CGI-WML-0.09.tar.gz
  DONSHANK/bbobj-1.0.tar.gz
  DROLSKY/Alzabo-GUI-Mason-0.10.tar.gz
  GRICHTER/HTML-Embperl-1.3.6.tar.gz
  HESCO/LedgerSMB-API-0.04.tar.gz
  JHIVER/TripleStore-0.02.tar.gz
  RKILGORE/Speech-Recognizer-ViaVoice-0.01.tar.gz
  THEDEVIL/Debarnacle-0.02.tar.gz
  ULPFR/WAIT-1.800.tar.gz
  EGOR/Alien-ghostty-0.02.tar.gz
);
my @Allowed = qw(
  ETHER/mod_perl-2.0.13.tar.gz
  PJCJ/Devel-Cover-1.50.tar.gz
  OTHER/Apache-Filter-1.024.tar.gz
  DROLSKY/Alzabo-0.92.tar.gz
  PLICEASE/Alien-Base-2.80.tar.gz
);

is refusals($_), 1, "$_ is refused by one prefs file" for @Refused;
is refusals($_), 0, "$_ is not refused"               for @Allowed;

done_testing;

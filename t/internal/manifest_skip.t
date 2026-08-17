#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# Dist::Zilla gathers every file in the working tree, dotfiles included, and
# MANIFEST.SKIP is the only filter, so working files must be skipped and
# nothing unexpected may reach the CPAN tarball.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use ExtUtils::Manifest qw( maniskip );
use File::Find         qw( find );

use Test::More import => [qw( diag done_testing is ok plan )];

plan skip_all => "must run from the root of a git checkout"
  unless -d ".git" && -e "dist.ini" && -e "MANIFEST.SKIP";

my $Skip = maniskip;

sub test_working_paths_are_skipped () {
  my @paths = qw(
    llm/todo.md
    llm/plans/GH-1/status.md
    dc_cover_lib_db/runs/x
    local/lib/perl5/Foo.pm
    .claude/settings.local.json
    .test_info.123.json
    Cover.def
    tags
    tags.tmp
    .perl-version
  );
  ok $Skip->($_), "$_ is skipped" for @paths;
}

sub test_shipped_paths_are_kept () {
  my @paths = qw(
    docs/perl-version-update.md
    docs/montags.md
    utils/tags
  );
  ok !$Skip->($_), "$_ is kept" for @paths;
}

sub test_only_expected_entries_survive () {
  my %expected = map { $_ => 1 } qw(
    .codespell .dprint.json .editorconfig .gitattributes .github .gitignore
    .hadolint.yaml .jscpd.json .markdownlint.yaml .mdformat.toml .perlcriticrc
    .perlimports.toml .perltidyrc .pre-commit-config.yaml .shellcheckrc
    .typos.toml .yamllint Changes Contributors Cover.xs MANIFEST.SKIP
    Makefile.PL README.md SECURITY.md bin dist.ini docker docs lib t
    test_output tests utils xt
  );
  my %stray;
  find sub {
    if (-d && $_ eq ".git") { $File::Find::prune = 1; return }
    return unless -f;
    my $name = $File::Find::name =~ s|^\./||r;
    return if $Skip->($name);
    my ($top) = $name =~ m|^([^/]+)|;
    $stray{$top}++ unless $expected{$top};
  }, ".";
  is join(" ", sort keys %stray), "", "no stray files survive MANIFEST.SKIP"
    or diag "add working files to MANIFEST.SKIP"
    . " or distribution files to the expected list";
}

sub main () {
  test_working_paths_are_skipped;
  test_shipped_paths_are_kept;
  test_only_expected_entries_survive;
  done_testing;
}

main;

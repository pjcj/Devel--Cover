#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Cwd        qw( getcwd realpath );
use File::Spec ();
use File::Temp qw( tempdir );

use Test::More import => [qw( diag done_testing is like ok plan unlike )];

use Devel::Cover::DB ();

my $Project   = getcwd;
my $Blib_lib  = File::Spec->catdir($Project, "blib", "lib");
my $Blib_arch = File::Spec->catdir($Project, "blib", "arch");

# A self-referential regex embeds its own compiled pattern through a (??{...})
# postponed code block.  That block compiles into an anonymous CV whose optree,
# for a recursive pattern, wraps the qr op in a nulled UNOP.  The old B::Deparse
# coverage collector walked whole subs through B::Deparse, which reaches
# $cv->ROOT->first->code_list and dies "Can't locate object method code_list via
# package B::UNOP", aborting the whole run and losing every file's coverage
# (GH-601).  The XS op walker collects statements directly and never deparses
# the block, so the run completes.  Guard against a return to a deparse-based
# walk.

# The pattern must sit inside a sub - that is the body the collector walks.
my $Program = <<'PROG';
sub munge {
  my $q = qr/\{\\hskip0pt +plus +0?.02em\}/;
  my $p; $p = qr/\{\s*(?:(?>$q)|(??{$p}))*\s*\}/;
  my $m = '{\\hskip0pt plus .02em}';
  local $_ = shift;
  s/$p/$m/g;
  $_
}
print munge('{\hskip0pt}1{\hskip0pt plus .02em}2'), "\n";
PROG

# Run $Program under coverage and return its exit code, output and the cover
# object for its file.
sub covered_program () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $prog   = File::Spec->catfile($tmpdir, "prog.pl");
  open my $fh, ">", $prog or die "Cannot write $prog: $!";
  print $fh $Program;
  close $fh or die "Cannot close $prog: $!";

  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd
    = "$^X -I$Blib_lib -I$Blib_arch"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0"
    . " $prog 2>&1";
  my $out = `$cmd`;

  my $db     = Devel::Cover::DB->new(db => $cover_db)->merge_runs;
  my ($file) = grep m|\Qprog.pl\E$|, $db->cover->items;
  ($? >> 8, $out, $file && $db->cover->file($file))
}

sub main () {
  plan skip_all => "blib not built" unless -d $Blib_lib && -d $Blib_arch;

  my ($rc, $out, $cover) = covered_program;

  is $rc, 0, "recursive-regex program runs under coverage" or diag $out;
  unlike $out, qr/code_list|Oops|went wrong/,
    "no B::Deparse code_list crash writing the coverage";
  like $out, qr/plus \.02em/, "the program's own output is intact";

  ok $cover, "the program file is in the coverage database" or do {
    done_testing;
    return;
  };

  my $stmt = $cover->statement;
  ok $stmt->location(6), "the substitution statement is collected"
    and is $stmt->location(6)->[0]->covered, 1, "and ran once";

  done_testing;
}

main;

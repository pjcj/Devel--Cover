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
use Test::More import => [qw( done_testing is_deeply ok plan )];
use Devel::Cover::Test::Showcase qw( slurp );

BEGIN {
  eval { require Template; Template->VERSION(2.00); 1 }
    or plan skip_all => "Template Toolkit not available";
}

use Devel::Cover::Report::Html_subtle ();

{

  package Mock::Sub;
  sub new        ($class, $name) { bless { name => $name }, $class }
  sub name       ($self)         { $self->{name} }
  sub percentage ($self)         { 100 }
}

{

  package Mock::Criterion;
  sub new ($class, @locations) { bless { locations => \@locations }, $class }
  sub items ($self) { map $_->[0], $self->{locations}->@* }

  sub location ($self, $loc) { [
    map Mock::Sub->new($_->[1]),
    grep { $_->[0] == $loc } $self->{locations}->@*,
  ] }
}

{

  package Mock::File;
  sub new        ($class, $crit) { bless { crit => $crit }, $class }
  sub subroutine ($self)         { $self->{crit} }
}

{

  package Mock::Cover;
  sub new  ($class, $file) { bless { file => $file }, $class }
  sub file ($self, $name)  { $self->{file} }
}

{

  package Mock::DB;

  sub new ($class, $cover) {
    bless { cover => $cover, db => "mock", criteria => [] }, $class
  }
  sub cover        ($self) { $self->{cover} }
  sub criteria     ($self) { $self->{criteria}->@* }
  sub all_criteria ($self) { $self->{criteria}->@* }
}

# The name sort in print_subroutines is stable, so same-named subs keep the
# order the locations were visited in.  Hash order can coincidentally ascend,
# so feed a fixed non-ascending order.
sub test_rows_sorted () {
  my $tmpdir = tempdir(CLEANUP => 1);
  my $src    = "$tmpdir/Mock.pm";
  open my $fh, ">", $src or die "Cannot write $src: $!";
  print $fh "package Mock;\n1;\n";
  close $fh or die "Cannot close $src: $!";

  my $crit = Mock::Criterion->new([12, "BEGIN"], [3, "BEGIN"], [7, "foo"]);
  my $db   = Mock::DB->new(Mock::Cover->new(Mock::File->new($crit)));
  $db->{summary}{$src}
    = { total => { percentage => 100 }, subroutine => { percentage => 100 } };

  local $Devel::Cover::Silent = 1;
  Devel::Cover::Report::Html_subtle->report(
    $db, {
      outputdir => $tmpdir,
      file      => [$src],
      show      => { subroutine => 1 },
      option    => { outputfile => "coverage.html" },
    },
  );

  my ($page) = glob "$tmpdir/*--subroutine.html";
  ok $page, "subroutine page generated";
  my @rows = slurp($page) =~ /<a id="line(\d+)"> (\w+) /g;
  is_deeply \@rows, [3, "BEGIN", 12, "BEGIN", 7, "foo"],
    "rows sorted by name then line";
}

sub main () {
  test_rows_sorted;
  done_testing;
}

main;

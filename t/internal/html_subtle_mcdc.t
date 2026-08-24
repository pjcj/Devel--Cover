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
use Test::More import => [qw( done_testing like ok plan )];
use Devel::Cover::Test::Showcase qw( slurp );

BEGIN {
  eval { require Template; Template->VERSION(2.00); 1 }
    or plan skip_all => "Template Toolkit not available";
}

use Devel::Cover::Mcdc                ();  ## no perlimports
use Devel::Cover::Report::Html_subtle ();

{

  package Mock::Criterion;
  sub new ($class, @locations) { bless { locations => \@locations }, $class }
  sub items ($self) { map $_->[0], $self->{locations}->@* }

  sub location ($self, $loc) {
    [map $_->[1], grep { $_->[0] == $loc } $self->{locations}->@*]
  }
}

{

  package Mock::File;
  sub new  ($class, $crit) { bless { crit => $crit }, $class }
  sub mcdc ($self)         { $self->{crit} }
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

# A stale atomic - run despite its marker - is an error, so it must not
# take the covered class. An excused atomic is not an error and keeps it.
sub test_atomic_classes () {
  my $tmpdir = tempdir(CLEANUP => 1);
  my $src    = "$tmpdir/Mock.pm";
  open my $fh, ">", $src or die "Cannot write $src: $!";
  print $fh "package Mock;\n1;\n";
  close $fh or die "Cannot close $src: $!";

  my $m = bless [[1, 0], { text => '$a || $b', labels => ["a", "b"] }, [1, 1]],
    "Devel::Cover::Mcdc";
  my $crit = Mock::Criterion->new([1, $m]);
  my $db   = Mock::DB->new(Mock::Cover->new(Mock::File->new($crit)));
  $db->{summary}{$src}
    = { total => { percentage => 100 }, mcdc => { percentage => 50 } };

  local $Devel::Cover::Silent = 1;
  Devel::Cover::Report::Html_subtle->report(
    $db, {
      outputdir => $tmpdir,
      file      => [$src],
      show      => { mcdc       => 1 },
      option    => { outputfile => "coverage.html" },
    },
  );

  my ($page) = glob "$tmpdir/*--mcdc.html";
  ok $page, "mcdc page generated";
  my $html = slurp($page);
  like $html, qr|<span class="uncovered">-a</span>|,
    "stale atomic takes the uncovered class";
  like $html, qr|<span class="covered">-b</span>|,
    "excused atomic keeps the covered class";
}

sub main () {
  test_atomic_classes;
  done_testing;
}

main;

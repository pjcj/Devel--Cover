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

use Test::More import => [qw( done_testing is_deeply )];
use Devel::Cover::Report::Text ();

{

  package Mock::Sub;
  sub new         ($class, $name) { bless { name => $name }, $class }
  sub name        ($self)         { $self->{name} }
  sub covered     ($self)         { 1 }
  sub uncoverable ($self)         { 0 }
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
  sub new             ($class, $cover) { bless { cover => $cover }, $class }
  sub cover           ($self)          { $self->{cover} }
  sub scar_sub_lookup ($self, $)       { {} }
}

# Same-named subs sorted by their location string put line 12 before line 9,
# so use lines either side of a digit-count boundary, fed in visit order 12
# then 9 so hash order can't accidentally produce the expected result.
sub test_locations_numeric () {
  my $crit = Mock::Criterion->new([12, "BEGIN"], [9, "BEGIN"], [5, "foo"]);
  my $db   = Mock::DB->new(Mock::Cover->new(Mock::File->new($crit)));

  my $output;
  {
    open my $fh, ">", \$output or die "Cannot open scalar ref: $!";
    local *STDOUT = $fh;
    Devel::Cover::Report::Text::print_subroutines(
      $db, "Mock.pm",
      { show      => {} },
      { "Mock.pm" => "Mock.pm" },
    );
    close $fh or die "Cannot close scalar ref: $!";
  }

  my @rows = $output =~ /^(\S+)\s+\d+\s+(\S+:\d+)/gm;
  is_deeply \@rows,
    ["BEGIN", "Mock.pm:9", "BEGIN", "Mock.pm:12", "foo", "Mock.pm:5"],
    "same-named subs listed in numeric line order";
}

sub main () {
  test_locations_numeric;
  done_testing;
}

main;

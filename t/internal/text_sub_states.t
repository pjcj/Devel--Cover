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

use Test::More import => [qw( done_testing is like unlike )];

use Devel::Cover::Pod          ();  ## no perlimports
use Devel::Cover::Report::Text ();  ## no perlimports
use Devel::Cover::Subroutine   ();  ## no perlimports

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

  sub new ($class, $subs, $pods = undef) {
    bless { subs => $subs, pods => $pods }, $class
  }
  sub subroutine ($self) { $self->{subs} }
  sub pod        ($self) { $self->{pods} }
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

sub sub_obj ($covered, $name, $uncoverable = 0) {
  bless [$covered, $name, $uncoverable], "Devel::Cover::Subroutine"
}

sub pod_obj ($covered, $uncoverable = 0) {
  bless [$covered, undef, $uncoverable], "Devel::Cover::Pod"
}

sub run_report ($subs, $pods = undef, $show = {}) {
  my $file = Mock::File->new($subs, $pods);
  my $db   = Mock::DB->new(Mock::Cover->new($file));

  my $output;
  {
    open my $fh, ">", \$output or die "Cannot open scalar ref: $!";
    local *STDOUT = $fh;
    Devel::Cover::Report::Text::print_subroutines(
      $db, "Mock.pm",
      { show      => $show },
      { "Mock.pm" => "Mock.pm" },
    );
    close $fh or die "Cannot close scalar ref: $!";
  }
  $output
}

sub section ($output, $heading) {
  $output =~ /^\Q$heading\E\n-+\n\n(.*?)(?:\n\n|\z)/ms ? $1 : ""
}

sub test_bucketing_by_state () {
  my $subs = Mock::Criterion->new(
    [5, sub_obj(1, "alpha")],
    [6, sub_obj(0, "beta")],
    [7, sub_obj(0, "gamma", 1)],
    [8, sub_obj(1, "delta", 1)],
  );
  my $output = run_report($subs);

  my $covered = section($output, "Covered Subroutines");
  like $covered, qr/^alpha\s+1\s+Mock\.pm:5$/m,
    "covered sub listed in the covered section";
  like $covered, qr/^delta\s+\*-1\s+Mock\.pm:8$/m,
    "covered but marked sub shows the error and uncoverable prefixes";

  my $uncoverable = section($output, "Uncoverable Subroutines");
  like $uncoverable, qr/^gamma\s+-0\s+Mock\.pm:7$/m,
    "excused sub listed in the uncoverable section";

  my $uncovered = section($output, "Uncovered Subroutines");
  like $uncovered, qr/^beta\s+0\s+Mock\.pm:6$/m,
    "uncovered sub keeps its bare count";
  unlike $uncovered, qr/gamma/, "excused sub not listed as uncovered";
}

sub test_section_order () {
  my $subs = Mock::Criterion->new(
    [5, sub_obj(1, "alpha")],
    [6, sub_obj(0, "beta")],
    [7, sub_obj(0, "gamma", 1)],
  );
  my $output   = run_report($subs);
  my @headings = $output =~ /^(\w+ Subroutines)$/mg;
  is "@headings",
    "Covered Subroutines Uncoverable Subroutines Uncovered Subroutines",
    "sections appear in sorted order";
}

sub test_pod_states () {
  my $subs
    = Mock::Criterion->new([5, sub_obj(1, "alpha")], [6, sub_obj(1, "beta")]);
  my $pods    = Mock::Criterion->new([5, pod_obj(0, 1)], [6, pod_obj(1, 1)]);
  my $output  = run_report($subs, $pods, { pod => 1 });
  my $covered = section($output, "Covered Subroutines");
  like $covered, qr/^alpha\s+1\s+-0\s+Mock\.pm:5$/m,
    "excused pod keeps the uncoverable prefix";
  like $covered, qr/^beta\s+1\s+\*-1\s+Mock\.pm:6$/m,
    "covered but marked pod shows the error and uncoverable prefixes";
}

sub main () {
  test_bucketing_by_state;
  test_section_order;
  test_pod_states;
  done_testing;
}

main

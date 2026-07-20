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

use Test::More import => [qw( diag done_testing is is_deeply like )];
use Devel::Cover::Report::Compilation ();
use Devel::Cover::Test::Showcase      qw(
  create_cover_db
  run_cover
  setup_lib_dir
);

# The compilation reporter emits one line per uncovered location in a format
# similar to Perl's own compilation errors, so editors with a quickfix-style
# error navigator can step through them.
sub test_compilation_report () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "compilation",
    "--silent",     $cover_db,
  );

  is $exit, 0, "cover --report compilation exits 0" or diag $out;

  like $out, qr/Uncovered statement at .* line \d+/,
    "uncovered statement line emitted";
  like $out, qr/Uncovered subroutine \S+ at .* line \d+/,
    "uncovered subroutine line emitted";
  like $out, qr|Uncovered MC/DC pair \([^)]*\) at .* line \d+: .+|,
    "uncovered MC/DC pair line emitted";

  my %stmt_lines;
  while ($out =~ /^Uncovered statement at (\S+) line (\d+)$/gm) {
    push $stmt_lines{$1}->@*, $2;
  }
  for my $file (sort keys %stmt_lines) {
    is_deeply $stmt_lines{$file}, [sort { $a <=> $b } $stmt_lines{$file}->@*],
      "statement lines ascending for $file";
  }
}

{

  package Mock::Item;
  sub new     ($class) { bless {}, $class }
  sub covered ($self)  { 0 }
  sub name    ($self)  { "mock_sub" }
}

{

  package Mock::Criterion;
  sub new   ($class, @locations) { bless { locations => \@locations }, $class }
  sub items ($self)              { $self->{locations}->@* }
  sub location ($self, $loc)     { [Mock::Item->new] }
}

{

  package Mock::File;
  sub new        ($class, $crit) { bless { crit => $crit }, $class }
  sub statement  ($self)         { $self->{crit} }
  sub subroutine ($self)         { $self->{crit} }
  sub pod        ($self)         { $self->{crit} }
}

{

  package Mock::Cover;
  sub new  ($class, $file) { bless { file => $file }, $class }
  sub file ($self, $name)  { $self->{file} }
}

{

  package Mock::DB;
  sub new   ($class, $cover) { bless { cover => $cover }, $class }
  sub cover ($self)          { $self->{cover} }
}

sub capture_lines ($print_sub) {
  my $crit = Mock::Criterion->new(10, 2, 19, 7, 13);
  my $db   = Mock::DB->new(Mock::Cover->new(Mock::File->new($crit)));
  my $output;
  {
    open my $fh, ">", \$output or die "Cannot open scalar ref: $!";
    local *STDOUT = $fh;
    $print_sub->($db, "Mock.pm", {});
    close $fh or die "Cannot close scalar ref: $!";
  }
  [$output =~ /line (\d+)$/gm]
}

# Hash order can coincidentally ascend, so feed a fixed non-ascending order.
sub test_lines_sorted () {
  my %print = (
    statement  => \&Devel::Cover::Report::Compilation::print_statement,
    subroutine => \&Devel::Cover::Report::Compilation::print_subroutines,
    pod        => \&Devel::Cover::Report::Compilation::print_pod,
  );
  for my $criterion (sort keys %print) {
    my $lines = capture_lines($print{$criterion});
    is_deeply $lines, [2, 7, 10, 13, 19],
      "$criterion lines emitted in ascending order";
  }
}

sub main () {
  test_compilation_report;
  test_lines_sorted;
  done_testing;
}

main;

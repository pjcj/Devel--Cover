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

use Test::More import =>
  [qw( diag done_testing is is_deeply like ok plan unlike )];
use Devel::Cover::Test::Showcase qw(
  create_cover_db
  run_cover
  setup_lib_dir
  slurp
);

eval "require Template; 1" or do {
  plan skip_all => "Template not available";
  exit;
};

sub markers_line ($libdir, $pattern) {
  my @lines = split /\n/, slurp("$libdir/Covered/Markers.pm");
  for my $i (0 .. $#lines) {
    return $i + 1 if $lines[$i] =~ $pattern;
  }
  die "No line matching $pattern in Covered/Markers.pm";
}

sub markers_list ($vim, $name) {
  my ($section) = $vim             =~ m{Covered/Markers\.pm':(.*?)\n\\\s*\},}s;
  my ($list)    = ($section // "") =~ /'\Q$name\E': \[([^\]]*)\]/;
  [($list // "") =~ /(\d+)/g]
}

# Stored file keys must be matched as literal text, not as Vim regexes
sub test_vim_report_literal_matching ($vim) {
  my $regex   = 'match(a:filename, s:f . "$")';
  my $literal = q[match(a:filename, '\V' . escape(s:f, '\') . '\$')];
  unlike $vim, qr/\Q$regex\E/,
    "file matching does not build a regex from the raw path";
  like $vim, qr/\Q$literal\E/,
    "file matching uses a very-nomagic literal pattern";
}

# Each criterion needs an uncoverable highlight and sign definition
sub test_uncoverable_definitions ($vim) {
  for my $type (qw( pod subroutine statement branch condition mcdc )) {
    like $vim, qr/^highlight cov_${type}_uncoverable\b.*Grey/m,
      "grey highlight defined for $type";
    my $sign = "sign define ${type}_uncoverable\n"
      . "    \\ linehl=unc texthl=cov_${type}_uncoverable";
    like $vim, qr/^\Q$sign\E/m, "sign defined for $type";
  }
}

# Sign priority: error beats excused beats covered, so the types list
# must run covered, uncoverable, error (placement is reversed first-wins)
sub test_types_priority_order ($vim) {
  my ($list) = $vim =~ /^let s:types = \[(.*?)\]/ms;
  ok defined $list, "types list found in coverage.vim";
  my @names = ($list // "") =~ /"(\w+)"/g;
  my @base  = grep !/_error$|_uncoverable$/, @names;
  ok @base >= 4, "several criteria collected" or diag "@base";
  is_deeply \@names,
    [@base, (map "${_}_uncoverable", @base), (map "${_}_error", @base)],
    "types ordered covered, uncoverable, error";
}

# Excused constructs go in the uncoverable lists, stale markers stay errors
sub test_excused_and_stale_lines ($vim, $libdir) {
  # subroutine coverage is recorded on the first statement's line
  my $excused = markers_line($libdir, qr/die "emergency stop"/);
  my $stale   = markers_line($libdir, qr/return "still called"/);

  my $st_unc = markers_list($vim, "statement_uncoverable");
  my $st_err = markers_list($vim, "statement_error");
  my $st_cov = markers_list($vim, "statement");

  ok grep($_ == $excused, @$st_unc), "excused statement listed uncoverable";
  is grep($_ == $excused, @$st_err), 0, "excused statement is not an error";
  is grep($_ == $excused, @$st_cov), 0, "excused statement is not covered";
  ok grep($_ == $stale,   @$st_err), "stale marker stays an error";
  is grep($_ == $stale,   @$st_unc), 0, "stale marker is not excused";

  my $sub_unc = markers_list($vim, "subroutine_uncoverable");
  my $sub_err = markers_list($vim, "subroutine_error");
  ok grep($_ == $excused, @$sub_unc), "excused subroutine listed uncoverable";
  ok grep($_ == $stale,   @$sub_err), "stale subroutine marker stays an error";
}

sub main () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "vim", "--silent", $cover_db,
  );
  is $exit, 0, "cover --report vim exits 0" or diag $out;
  my $vim = slurp("$cover_db/coverage.vim");

  test_vim_report_literal_matching($vim);
  test_uncoverable_definitions($vim);
  test_types_priority_order($vim);
  test_excused_and_stale_lines($vim, $libdir);
  done_testing;
}

main;

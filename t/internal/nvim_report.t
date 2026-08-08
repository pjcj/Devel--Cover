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

sub markers_list ($lua, $name) {
  my ($section) = $lua =~ m{Covered/Markers\.pm"\] = \{(.*?)\n  \},}s;
  my ($list)    = ($section // "") =~ /\b\Q$name\E = \{([^}]*)\}/;
  [($list // "") =~ /(\d+)/g]
}

# Stored file keys must be matched as literal text, not as Lua patterns
sub test_nvim_report_literal_matching ($lua) {
  my $pattern = 'string.find(filename, f .. "$")';
  my $literal = "string.sub(filename, -#f) == f";
  unlike $lua, qr/\Q$pattern\E/,
    "file matching does not build a Lua pattern from the path";
  like $lua, qr/\Q$literal\E/, "file matching uses a literal suffix comparison";
}

# The template's sign_priority default and the POD's documented one must agree
sub test_sign_priority_default_documented () {
  require Devel::Cover::Report::Nvim;
  my $src = slurp($INC{"Devel/Cover/Report/Nvim.pm"});
  my ($code_default)
    = $src =~ /sign_priority = vim\.g\.devel_cover_sign_priority or (\d+),/;
  my ($pod_default)
    = $src =~ /devel_cover_sign_priority\s+-- Sign priority \(default: (\d+)\)/;
  ok defined $code_default, "template sign_priority default found";
  ok defined $pod_default,  "POD sign_priority default found";
  is $pod_default, $code_default, "POD documents the template default";
}

# Each criterion needs an uncoverable highlight and sign definition
sub test_uncoverable_definitions ($lua) {
  like $lua, qr/uncoverable_fg = vim\.g\.devel_cover_uncoverable_fg or "Grey"/,
    "uncoverable foreground configurable, default grey";
  like $lua, qr/"cov_" \.\. type_name \.\. "_uncoverable"/,
    "uncoverable highlight groups created";
  like $lua, qr/type_name \.\. "_uncoverable", \{/, "uncoverable signs defined";
  like $lua, qr/linehl_uncoverable/, "uncoverable line highlight configured";
}

# Sign priority: error beats excused beats covered, so the types list
# must run covered, uncoverable, error (placement is reversed first-wins)
sub test_types_priority_order ($lua) {
  my ($list) = $lua =~ /^local types = \{(.*?)\}/ms;
  ok defined $list, "types list found in coverage.lua";
  my @names = ($list // "") =~ /"(\w+)"/g;
  my @base  = grep !/_error$|_uncoverable$/, @names;
  ok @base >= 4, "several criteria collected" or diag "@base";
  is_deeply \@names,
    [@base, (map "${_}_uncoverable", @base), (map "${_}_error", @base)],
    "types ordered covered, uncoverable, error";
}

# Excused constructs go in the uncoverable lists, stale markers stay errors
sub test_excused_and_stale_lines ($lua, $libdir) {
  # subroutine coverage is recorded on the first statement's line
  my $excused = markers_line($libdir, qr/die "emergency stop"/);
  my $stale   = markers_line($libdir, qr/return "still called"/);

  my $st_unc = markers_list($lua, "statement_uncoverable");
  my $st_err = markers_list($lua, "statement_error");
  my $st_cov = markers_list($lua, "statement");

  ok grep($_ == $excused, @$st_unc), "excused statement listed uncoverable";
  is grep($_ == $excused, @$st_err), 0, "excused statement is not an error";
  is grep($_ == $excused, @$st_cov), 0, "excused statement is not covered";
  ok grep($_ == $stale,   @$st_err), "stale marker stays an error";
  is grep($_ == $stale,   @$st_unc), 0, "stale marker is not excused";

  my $sub_unc = markers_list($lua, "subroutine_uncoverable");
  my $sub_err = markers_list($lua, "subroutine_error");
  ok grep($_ == $excused, @$sub_unc), "excused subroutine listed uncoverable";
  ok grep($_ == $stale,   @$sub_err), "stale subroutine marker stays an error";
}

sub main () {
  my ($tmpdir, $libdir) = setup_lib_dir;
  my $cover_db = create_cover_db($tmpdir, $libdir);

  my ($out, $exit) = run_cover(
    "--select_dir", $libdir, "--report", "nvim", "--silent", $cover_db,
  );
  is $exit, 0, "cover --report nvim exits 0" or diag $out;
  my $lua = slurp("$cover_db/coverage.lua");

  test_nvim_report_literal_matching($lua);
  test_sign_priority_default_documented;
  test_uncoverable_definitions($lua);
  test_types_priority_order($lua);
  test_excused_and_stale_lines($lua, $libdir);
  done_testing;
}

main;

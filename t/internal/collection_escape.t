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

use Test::More import => [qw( done_testing is like plan unlike )];

eval "require HTML::Entities; 1" or do {
  plan skip_all => "HTML::Entities not available";
  exit;
};
eval "require Template; 1" or do {
  plan skip_all => "Template not available";
  exit;
};
# Collection uses the feature "class" and needs a recent Perl.
eval "require Devel::Cover::Collection; 1" or do {
  plan skip_all => "Devel::Cover::Collection not available: $@";
  exit;
};

# The cpancover collection index lists every distribution's name and version.
# Both come from the module's own cover.json (or its directory name), so they
# may contain markup characters and must be escaped before being written.
my $Meta = "x<MARK>&";

sub render_index () {
  my $template = Template->new({
    LOAD_TEMPLATES => [Devel::Cover::Collection::Template::Provider->new({})],
  });

  my $vars = {
    title        => "Coverage report",
    root         => "",
    module_start => "E",
    criteria     => [],
    col_headers  => [{ full => "Total", short => "total" }],
    modules      => {
      E =>
        [{ module => "Test-1.0", name => $Meta, version => "1.0$Meta" }],
    },
    vals => { "Test-1.0" => {} },
  };

  my $out = "";
  $template->process("module_by_start", $vars, \$out) or die $template->error;
  $out
}

sub main () {
  my $html = render_index;
  unlike $html, qr|<MARK>|, "collection index does not emit raw module metadata";
  like $html,   qr|&lt;MARK&gt;|, "collection index escapes module metadata";

  done_testing;
}

main;

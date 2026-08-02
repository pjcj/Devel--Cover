#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();  ## no perlimports
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Cwd        qw( getcwd );
use File::Path qw( make_path );
use File::Temp ();
use JSON::PP   ();
use Test::More import => [qw( done_testing is like plan unlike )];

BEGIN {
  plan skip_all => "Devel::Cover::Collection requires Perl 5.42" if $] < 5.042;
  plan skip_all => "Devel::Cover::Collection is not portable to Windows"
    if $^O eq "MSWin32";
  for my $module (qw( Template Parallel::Iterator JSON::MaybeXS )) {
    plan skip_all => "$module required for this test"
      unless eval "require $module; 1";
  }
}

use Devel::Cover::Collection ();
use Devel::Cover::Inc        ();

my $Dist    = "Foo-Bar-1.00";
my $Log     = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--1234567890.123456.out.gz";
my $Log_new = "P-PJ-PJCJ-Foo-Bar-1.00.tar.gz--1234567899.123456.out.gz";
my $Dist2   = "Baz-Qux-2.00";
my $Log2    = "P-PJ-PJCJ-Baz-Qux-2.00.tar.gz--1234567891.123456.out";
my $Dist3   = "Dangle-Ref-3.00";
my $Log3    = "P-PJ-PJCJ-Dangle-Ref-3.00.tar.gz--1234567892.123456.out";
my $Ref3    = "P-PJ-PJCJ-Dangle-Ref-3.00.tar.gz--9999999999.123456.out";
my $Dist4   = "Dep-Only-4.00";
my $Dist5   = "No-Page-5.00";

sub write_file ($path, $content) {
  open my $fh, ">", $path or die "Can't open $path: $!";
  print $fh $content;
  close $fh or die "Can't close $path: $!";
}

sub slurp ($path) {
  open my $fh, "<", $path or die "Can't open $path: $!";
  local $/;
  my $content = <$fh>;
  close $fh or die "Can't close $path: $!";
  $content
}

sub write_dist (
  $dir, $dist, $name, $version, $log = undef,
  $page = 1, $scar = undef,
) {
  make_path("$dir/$dist");

  my $criterion = { percentage => 85.5, covered => 10, total => 12 };
  my $total     = { total => $criterion, statement => $criterion };
  $total->{scar} = $scar if $scar;
  my $cover = {
    runs    => [{ name => $name, version => $version, dir => "/tmp/x" }],
    summary => { Total => $total },
  };
  write_file("$dir/$dist/cover.json", JSON::PP->new->encode($cover));
  write_file("$dir/$dist/index.html", "report\n") if $page;
  write_file("$dir/$log",             "log\n")    if defined $log;
}

sub seed_page ($dir, $file) {
  write_file("$dir/$file", "old");
  link "$dir/$file", "$dir/$file.seeded"
    or plan skip_all => "hardlinks not supported";
}

my $Scar
  = { file_cc => 12, file_cov => 90, file_crap => 14.3, file_scar => 26.6 };

sub setup_results_dir {
  my $dir = File::Temp->newdir;
  write_dist($dir, $Dist, "Foo-Bar", "1.00", $Log, 1, $Scar);
  write_dist($dir, $Dist2, "Baz-Qux", "2.00", $Log2);

  # $Dist was rebuilt: .log_ref names the newer log, both logs remain
  write_file("$dir/$Log_new",       "log\n");
  write_file("$dir/$Dist/.log_ref", "$Log_new\n");

  # $Dist3 has a dangling .log_ref but a name-matching log
  write_dist($dir, $Dist3, "Dangle-Ref", "3.00", $Log3);
  write_file("$dir/$Dist3/.log_ref", "$Ref3\n");

  # $Dist4 was built as a dependency: no own log, .log_ref names the
  # target's log
  write_dist($dir, $Dist4, "Dep-Only", "4.00");
  write_file("$dir/$Dist4/.log_ref", "$Log_new\n");

  # $Dist5 has coverage totals but its report page was never written
  write_dist($dir, $Dist5, "No-Page", "5.00", undef, 0);

  make_path("$dir/dist");
  seed_page($dir, $_) for qw( index.html dist/F.html about.html );

  $dir
}

my $Cwd = getcwd;
my $Dir = setup_results_dir;

my $Collection = Devel::Cover::Collection->new(results_dir => "$Dir");
$Collection->generate_html;
chdir $Cwd or die "Can't chdir $Cwd: $!";

my %Page = (
  index  => slurp("$Dir/index.html"),
  dist   => slurp("$Dir/dist/F.html"),
  dist_b => slurp("$Dir/dist/B.html"),
  dist_d => slurp("$Dir/dist/D.html"),
  dist_n => slurp("$Dir/dist/N.html"),
  about  => slurp("$Dir/about.html"),
);

for my $name (sort keys %Page) {
  unlike $Page{$name}, qr{/latest/},        "$name page has no /latest/ links";
  unlike $Page{$name}, qr{(?:href|src)="/}, "$name page has no absolute links";
}

for my $name (qw( index about )) {
  like $Page{$name}, qr{href="collection\.css"},
    "$name page links stylesheet relatively";
  like $Page{$name}, qr{src="collection\.js"},
    "$name page links script relatively";
  like $Page{$name}, qr{href="about\.html"},
    "$name page links about page relatively";
  like $Page{$name}, qr{<h1><a href="index\.html">CPANCover</a></h1>},
    "$name page header links home";
}

like $Page{index}, qr{href="dist/F\.html"}, "index links dist page";

like $Page{dist}, qr{href="\.\./collection\.css"}, "dist page links stylesheet";
like $Page{dist}, qr{src="\.\./collection\.js"},   "dist page links script";
like $Page{dist}, qr{href="\.\./about\.html"},     "dist page links about page";
like $Page{dist}, qr{<h1><a href="\.\./index\.html">CPANCover</a></h1>},
  "dist page header links home";
like $Page{dist}, qr{href="\.\./\Q$Dist\E/index\.html"},
  "dist page links module report";
like $Page{dist_n}, qr{No-Page}, "dist without a report page is listed";
unlike $Page{dist_n}, qr{href="\.\./\Q$Dist5\E/index\.html"},
  "dist without a report page is not linked";
like $Page{dist}, qr{href="\.\./\Q$Log_new\E"},
  "dist page links the log named in .log_ref";
unlike $Page{dist}, qr{href="\.\./\Q$Log\E"},
  "dist page does not link the older log";
like $Page{dist_b}, qr{href="\.\./\Q$Log2\E"},
  "dist page links uncompressed build log";
like $Page{dist_d}, qr{href="\.\./\Q$Log3\E"},
  "dangling .log_ref falls back to the name-matched log";
unlike $Page{dist_d}, qr{href="\.\./\Q$Ref3\E"},
  "dangling .log_ref target is not linked";
like $Page{dist_d}, qr{href="\.\./\Q$Log_new\E"},
  "dependency dist links its target's log via .log_ref";

like $Page{dist}, qr{href="https://metacpan\.org/release/PJCJ/\Q$Dist\E"},
  "version links the metacpan release parsed from the log";
like $Page{dist_b}, qr{href="https://metacpan\.org/release/PJCJ/\Q$Dist2\E"},
  "version links the metacpan release for an uncompressed log";
like $Page{dist_d}, qr{href="https://metacpan\.org/release/PJCJ/\Q$Dist3\E"},
  "version links the metacpan release via the name-matched log";
like $Page{dist_d}, qr{href="https://metacpan\.org/dist/Dep-Only"},
  "dependency dist falls back to the metacpan dist link";
unlike $Page{dist_d}, qr{href="https://metacpan\.org/release/\w+/\Q$Dist4\E"},
  "dependency dist gets no release link from its target's log";

like $Page{dist}, qr{<th>CC</th>},                "dist page has a CC header";
like $Page{dist}, qr{<th>SCAR</th>},              "dist page has a SCAR header";
like $Page{dist}, qr{<td class="cc-val">12</td>}, "dist page shows CC";
my $Tip = quotemeta
  '<span class="glass-tip">CC 12 &middot; cov 90% &middot; CRAP 14.3</span>';
like $Page{dist},
  qr{<td class="scar-val scar-c2 tip-hover">26\.6\s*$Tip\s*</td>},
  "dist page shows SCAR with class and tip";
my @Na_cells = $Page{dist_b} =~ m{(<td class="na">n/a</td>)}g;
is @Na_cells, 2, "dist without scar data shows n/a for CC and SCAR";

my $Css = slurp("$Dir/collection.css");
like $Css, qr{td\.na[^{}]*\{[^{}]*text-align:\s*center}s,
  "n/a cells are centred";
like $Css, qr{th[^{}]*\{[^{}]*position:\s*sticky}s, "table headers are sticky";
like $Css, qr{th[^{}]*\{[^{}]*top:\s*calc\(var\(--header-height}s,
  "table headers stick below the page header";
like slurp("$Dir/collection.js"), qr{--header-height},
  "collection.js measures the page header height";

my $Search = JSON::PP->new->decode(slurp("$Dir/search.json"));
is join(",", sort @$Search),
  "Baz-Qux-2.00,Dangle-Ref-3.00,Dep-Only-4.00,Foo-Bar-1.00",
  "search.json lists only modules with report pages";
like $Page{index}, qr{<input[^>]*id="module-search"[^>]*data-root=""},
  "index page has the search input";
like $Page{dist}, qr{<input[^>]*id="module-search"[^>]*data-root="\.\./"},
  "dist page search input carries the root prefix";
like slurp("$Dir/collection.js"), qr{module-search},
  "collection.js wires up the search";

my $Cpancover = JSON::PP->new->decode(slurp("$Dir/cpancover.json"));
my $Coverage  = $Cpancover->{"Foo-Bar"}{"1.00"}{coverage}{total};
is join(",", sort keys %$Coverage), "statement,total",
  "cpancover.json has no cc or scar keys";

my $Version = $Devel::Cover::Inc::VERSION . $Devel::Cover::Inc::Dev;
for my $name (sort keys %Page) {
  like $Page{$name}, qr{Devel::Cover</a>\s+\Q$Version\E\s+by},
    "$name page footer shows the Devel::Cover version";
}

for my $f (qw( index.html dist/F.html about.html )) {
  is slurp("$Dir/$f.seeded"), "old", "$f is written atomically";
}
my @Tmp = map glob, "$Dir/*.tmp.*", "$Dir/dist/*.tmp.*";
is @Tmp, 0, "no tmp files remain";

done_testing;

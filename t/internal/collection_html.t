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
use Test::More import => [qw( done_testing is like ok plan unlike )];

BEGIN {
  plan skip_all => "Devel::Cover::Collection requires Perl 5.42" if $] < 5.042;
  plan skip_all => "Devel::Cover::Collection is not portable to Windows"
    if $^O eq "MSWin32";
  for my $module (
    qw( Template Parallel::Iterator JSON::MaybeXS CPAN::DistnameInfo )
  ) {
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
  # $Dist's metadata names the directory inside the archive, which is
  # behind the release, so the pages must take the name and version from
  # the distdir
  write_dist($dir, $Dist, "Foo-Bar-Inner", "0.99", $Log, 1, $Scar);

  # $Dist2's report predates the file_cc/file_cov/file_crap summary fields
  write_dist($dir, $Dist2, "Baz-Qux", "2.00", $Log2, 1, { file_scar => 26.6 });

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

  # An older version of $Dist, which the overview must not count
  write_dist($dir, "Foo-Bar-0.50", "Foo-Bar", "0.50");

  # A TRIAL of $Dist, whose metadata has no TRIAL marker, and a dist
  # with only a TRIAL
  write_dist($dir, "Foo-Bar-1.50-TRIAL",    "Foo-Bar",    "1.50");
  write_dist($dir, "Only-Trial-0.01-TRIAL", "Only-Trial", "0.01");

  # A dist with no coverage percentages, for the overview's n/a band
  make_path("$dir/Zero-Data-6.00");
  my $empty = {
    runs    => [{ name => "Zero-Data", version => "6.00", dir => "/tmp/x" }],
    summary => { Total => {} },
  };
  write_file("$dir/Zero-Data-6.00/cover.json", JSON::PP->new->encode($empty));

  make_path("$dir/dist");
  seed_page($dir, $_) for qw( index.html dist/F.html about.html );

  $dir
}

my ($Cwd, $Dir, $Collection, @Warnings, %Page, $Css);

sub generate () {
  $Cwd        = getcwd;
  $Dir        = setup_results_dir;
  $Collection = Devel::Cover::Collection->new(results_dir => "$Dir");
  {
    local $SIG{__WARN__} = sub { push @Warnings, @_ };
    $Collection->generate_html;
  }
  chdir $Cwd or die "Can't chdir $Cwd: $!";

  %Page = (
    index  => slurp("$Dir/index.html"),
    dist   => slurp("$Dir/dist/F.html"),
    dist_b => slurp("$Dir/dist/B.html"),
    dist_d => slurp("$Dir/dist/D.html"),
    dist_n => slurp("$Dir/dist/N.html"),
    dist_o => slurp("$Dir/dist/O.html"),
    about  => slurp("$Dir/about.html"),
  );
  $Css = slurp("$Dir/collection.css");
}

sub test_no_warnings () {
  is grep(/uninitialized/, @Warnings), 0,
    "generate_html emits no uninitialized warnings";
}

sub test_page_links () {
  for my $name (sort keys %Page) {
    unlike $Page{$name}, qr{/latest/}, "$name page has no /latest/ links";
    unlike $Page{$name}, qr{(?:href|src)="/},
      "$name page has no absolute links";
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

  like $Page{dist}, qr{href="\.\./collection\.css"},
    "dist page links stylesheet";
  like $Page{dist}, qr{src="\.\./collection\.js"}, "dist page links script";
  like $Page{dist}, qr{href="\.\./about\.html"},   "dist page links about page";
  like $Page{dist}, qr{<h1><a href="\.\./index\.html">CPANCover</a></h1>},
    "dist page header links home";
  like $Page{dist}, qr{href="\.\./\Q$Dist\E/index\.html"},
    "dist page links module report";
  like $Page{dist_n}, qr{No-Page}, "dist without a report page is listed";
  unlike $Page{dist_n}, qr{href="\.\./\Q$Dist5\E/index\.html"},
    "dist without a report page is not linked";
}

sub test_log_links () {
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
}

sub test_metacpan_links () {
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
}

sub test_cc_scar () {
  like $Page{dist}, qr{<th>CC</th>},   "dist page has a CC header";
  like $Page{dist}, qr{<th>SCAR</th>}, "dist page has a SCAR header";
  like $Page{dist}, qr{<td class="cc-val">12</td>}, "dist page shows CC";
  my $tip = quotemeta
    '<span class="glass-tip">CC 12 &middot; cov 90% &middot; CRAP 14.3</span>';
  like $Page{dist},
    qr{<td class="scar-val scar-c2 tip-hover">26\.6\s*$tip\s*</td>},
    "dist page shows SCAR with class and tip";
  my @na_cells = $Page{dist_b} =~ m{(<td class="na">n/a</td>)}g;
  is @na_cells, 2, "dist with incomplete scar data shows n/a for CC and SCAR";
  my @na_cells_n = $Page{dist_n} =~ m{(<td class="na">n/a</td>)}g;
  is @na_cells_n, 2, "dist without scar data shows n/a for CC and SCAR";
}

sub test_css () {
  like $Css, qr{td\.na[^{}]*\{[^{}]*text-align:\s*center}s,
    "n/a cells are centred";
  like $Css, qr{th[^{}]*\{[^{}]*position:\s*sticky}s,
    "table headers are sticky";
  like $Css, qr{th[^{}]*\{[^{}]*top:\s*calc\(var\(--header-height}s,
    "table headers stick below the page header";
  like slurp("$Dir/collection.js"), qr{--header-height},
    "collection.js measures the page header height";
}

sub test_overview_bar () {
  like $Page{index}, qr{<p class="dist-count">7 distributions</p>},
    "index page counts distributions once per name";
  like $Page{index},
    qr{<div class="dist-bar-seg c1" style="width: 85\.71%">\s*6\s*</div>},
    "index page bar has a c1 segment counting latest versions only";
  like $Page{index},
    qr{<div class="dist-bar-seg na" style="width: 14\.29%">\s*1\s*</div>},
    "index page bar has an n/a segment";
  like $Page{index}, qr{dist-bar-seg c1.*dist-bar-seg na}s,
    "bar segments run from best to worst";
  unlike $Page{index}, qr{dist-bar-seg c[023]}, "empty bands are omitted";
  like $Page{index},   qr{dist-bar.*az-nav}s,   "bar appears above the A-Z nav";
  like $Css, qr{\.dist-bar\b[^{}]*\{[^{}]*display:\s*flex}s,
    "bar segments lay out in a row";
  like $Css,
    qr{\.dist-bar-seg\.c1[^{}]*\{[^{}]*background:\s*var\(--cov-low-bg\)}s,
    "bar segments use the shared coverage colours";
}

sub test_overview_segments () {
  my $vars = {
    vals => {
      (
        map { ("Dist$_-1.00" => {
          module => { name => "Dist$_", version => "1.00" },
          total  => { pc   => "100.00" },
        }) } 1 .. 30
      ),
      "Low-1.00" => {
        module => { name => "Low", version => "1.00" },
        total  => { pc   => "50.00" },
      },
    },
  };
  $Collection->add_overview($vars);
  my $segments = $vars->{overview}{segments};
  is $segments->[-1]{label}, "",
    "segments too narrow for their count drop the label";
}

sub test_overview_trial () {
  my $vars = {
    vals => {
      "Foo-1.00" => {
        module => { name => "Foo", version => "1.00" },
        total  => { pc   => "100.00" },
      },
      "Foo-1.50-TRIAL" => {
        module => { name => "Foo", version => "1.50-TRIAL" },
        total  => { pc   => "50.00" },
      },
      "Bar-0.01-TRIAL" => {
        module => { name => "Bar", version => "0.01-TRIAL" },
        total  => { pc   => "50.00" },
      },
    },
  };
  $Collection->add_overview($vars);
  is $vars->{overview}{count}, 2, "overview counts each dist once";
  is join(",", map $_->{class}, $vars->{overview}{segments}->@*), "c3,c0",
    "a stable release outranks a newer TRIAL, a lone TRIAL still counts";
}

sub test_search () {
  my $search = JSON::PP->new->decode(slurp("$Dir/search.json"));
  is join(",", @$search), join(
    ",",
    qw( Baz-Qux-2.00 Dangle-Ref-3.00 Dep-Only-4.00 Foo-Bar-1.00 Foo-Bar-0.50
      Foo-Bar-1.50-TRIAL Only-Trial-0.01-TRIAL ),
    ),
    "search.json lists newest versions first, TRIALs last, report pages only";
  like $Page{index}, qr{<input[^>]*id="module-search"[^>]*data-root=""},
    "index page has the search input";
  like $Page{index}, qr{<input[^>]*placeholder="Search distributions"},
    "search placeholder says distributions";
  like $Page{dist}, qr{<input[^>]*id="module-search"[^>]*data-root="\.\./"},
    "dist page search input carries the root prefix";
  like slurp("$Dir/collection.js"), qr{module-search},
    "collection.js wires up the search";
}

sub test_cpancover_json () {
  my $cpancover = JSON::PP->new->decode(slurp("$Dir/cpancover.json"));
  my $coverage  = $cpancover->{"Foo-Bar"}{"1.00"}{coverage}{total};
  is join(",", sort keys %$coverage), "statement,total",
    "cpancover.json has no cc or scar keys";
  ok exists($cpancover->{"Foo-Bar"}{"1.50-TRIAL"}),
    "cpancover.json keys a TRIAL by its suffixed version";
  ok !exists($cpancover->{"Foo-Bar"}{"1.50"}),
    "cpancover.json does not key a TRIAL by its bare version";
  like $Page{dist}, qr{1\.50-TRIAL}, "dist page shows the TRIAL version";
  ok !exists($cpancover->{"Foo-Bar-Inner"}),
    "cpancover.json does not key a release by the name in its metadata";
  ok !exists($cpancover->{"Foo-Bar"}{"0.99"}),
    "cpancover.json does not key a release by the version in its metadata";
  unlike $Page{dist}, qr{Foo-Bar-Inner|0\.99},
    "dist page shows the release name and version, not the metadata";
}

sub test_version_footer () {
  my $version = $Devel::Cover::Inc::VERSION . $Devel::Cover::Inc::Dev;
  for my $name (sort keys %Page) {
    like $Page{$name}, qr{Devel::Cover</a>\s+\Q$version\E\s+by},
      "$name page footer shows the Devel::Cover version";
  }
}

sub test_version_comment () {
  my $version = $Devel::Cover::Inc::VERSION . $Devel::Cover::Inc::Dev;
  for my $name (sort keys %Page) {
    like $Page{$name}, qr/generated by Devel::Cover Version \Q$version\E$/m,
      "$name page comment shows the Devel::Cover version";
    unlike $Page{$name}, qr/\$VERSION/, "$name page has no literal \$VERSION";
  }
}

sub test_atomic_writes () {
  for my $f (qw( index.html dist/F.html about.html )) {
    is slurp("$Dir/$f.seeded"), "old", "$f is written atomically";
  }
  my @tmp = map glob, "$Dir/*.tmp.*", "$Dir/dist/*.tmp.*";
  is @tmp, 0, "no tmp files remain";
}

sub test_parallel_run () {
  my $parallel
    = Devel::Cover::Collection->new(results_dir => "$Dir", workers => 2);
  {
    local $SIG{__WARN__} = sub { push @Warnings, @_ };
    $parallel->generate_html;
  }
  chdir $Cwd or die "Can't chdir $Cwd: $!";
  is slurp("$Dir/index.html"), $Page{index},
    "a parallel run writes the same index page";
  is slurp("$Dir/dist/F.html"), $Page{dist},
    "a parallel run writes the same dist page";
}

sub test_about_environment () {
  like $Page{about}, qr{<h3>Build environment</h3>},
    "about page has a build environment section";
  my @vars = qw(
    AUTOMATED_TESTING NONINTERACTIVE_TESTING EXTENDED_TESTING
    PERL_MM_USE_DEFAULT
  );
  like $Page{about}, qr{<code>\Q$_\E=1</code>}, "about page documents $_"
    for @vars;
}

sub main () {
  generate;
  test_no_warnings;
  test_page_links;
  test_about_environment;
  test_log_links;
  test_metacpan_links;
  test_cc_scar;
  test_css;
  test_overview_bar;
  test_overview_segments;
  test_overview_trial;
  test_search;
  test_cpancover_json;
  test_version_footer;
  test_version_comment;
  test_atomic_writes;
  test_parallel_run;
}

main;
done_testing;

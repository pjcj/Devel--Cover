#!/usr/bin/perl

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

# A decision with more conditions than the analysis limit must not be
# silently excluded from MC/DC: it counts as 0 out of its width, carries an
# unanalysed flag, and report-time derivation warns, naming file and line.

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use FindBin ();
use lib "$FindBin::Bin/../lib", $FindBin::Bin,
  qw( ./lib ./blib/lib ./blib/arch );

use Test::More import => [qw( done_testing is like ok subtest unlike )];

use Devel::Cover::Test::Internal qw( write_script run_under_cover );

{
  no feature "signatures";

  sub capture_stderr (&) {
    my ($code) = @_;
    my $err = "";
    open my $save_err, ">&", \*STDERR or die "Cannot dup STDERR: $!";
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">", \$err or die "Cannot redirect STDERR: $!";
    my $result = $code->();
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">&", $save_err or die "Cannot restore STDERR: $!";
    ($err, $result)
  }
}

my @Vars = map "\$v$_", 1 .. 18;
my $Decl = "my (" . join(", ", @Vars) . ") = (0) x 18;";
my $Wide = "my \$r = " . join(" || ", @Vars) . ";";

# The narrow decision is fully exercised, so without the fix the file-level
# percentage would read 100 while the wide decision is silently excluded.
my $Narrow = <<'PERL';
sub narrow { my ($x, $y) = @_; my $r = $x && $y; $r }
narrow(0, 0);
narrow(1, 0);
narrow(1, 1);
PERL

# Line numbers in the generated script: narrow block is lines 1-4, the
# declaration line 5, the wide decision line 6.
my $Wide_line = 6;

sub run_wide ($label, $source) {
  my $script = write_script("$label.pl", $source);
  my ($db, $path)
    = run_under_cover($script, $label, criteria => [qw( condition mcdc )]);
  ($db, $path)
}

sub decisions ($db, $path) {
  my $mcdc = $db->cover->file($path)->{mcdc} // {};
  map { ($_->@*) } values %$mcdc
}

sub test_wide_decision_reported_unanalysed () {
  my ($db, $path) = run_wide("too_wide", "$Narrow$Decl\n$Wide\n");
  my ($err) = capture_stderr { $db->cover };

  my ($wide)   = grep { $_->total == 18 } decisions($db, $path);
  my ($narrow) = grep { $_->total == 2 } decisions($db, $path);

  ok $wide, "wide decision present in mcdc data";
  is $wide->covered, 0, "wide decision counts 0 of its width";
  ok $wide->error,       "wide decision carries an error flag";
  ok $wide->unanalysed,  "wide decision flagged unanalysed";
  is $wide->text, join(" || ", @Vars), "wide decision text preserved";

  ok $narrow, "narrow decision on the same file still analysed";
  is $narrow->covered, 2, "narrow decision fully covered";
  ok !$narrow->error,      "narrow decision has no error";
  ok !$narrow->unanalysed, "narrow decision not flagged unanalysed";

  like $err, qr/18 conditions.*limit of 16/,
    "warning names the width and the limit";
  like $err, qr/\Q$path\E:$Wide_line\b/, "warning names file and line";
}

sub test_warning_respects_silent () {
  my ($db, $path) = run_wide("too_wide_silent", "$Narrow$Decl\n$Wide\n");
  my ($err) = do {
    local $Devel::Cover::Silent = 1;
    capture_stderr { $db->cover };
  };
  is $err, "", "no warning under -silent";

  my ($wide) = grep { $_->total == 18 } decisions($db, $path);
  ok $wide && $wide->unanalysed, "decision still flagged unanalysed";
}

sub test_uncoverable_marker_ignored_with_warning () {
  my $source = "$Narrow$Decl\n# uncoverable mcdc\n$Wide\n";
  my ($db, $path) = run_wide("too_wide_unc", $source);
  my ($err) = capture_stderr { $db->cover };

  my ($wide) = grep { $_->total == 18 } decisions($db, $path);
  ok $wide, "wide decision present";
  is $wide->uncoverable, 0, "uncoverable marker not applied";
  ok $wide->error, "decision still reports an error";

  my $line = $Wide_line + 1;  # the marker comment shifts the decision down
  like $err, qr/Ignoring uncoverable mcdc at \Q$path\E:$line\b/,
    "marker on a too-wide decision warns and is ignored";
}

sub slurp ($path) {
  open my $fh, "<", $path or die "Cannot read $path: $!";
  my $content = do { local $/; <$fh> };
  close $fh or die "Cannot close $path: $!";
  $content
}

# Each HTML reporter must render the note in place of the wide decision's
# atomic pills.  The narrow decision's pills, the wide decision's text and
# the highlighted source all legitimately mention wide-only variables, so
# the absence assertion targets each reporter's own pill markup.
sub pill_re ($report, $var) {
  my %re = (
    html_basic   => qr|<span class="c[03]">\s*\Q$var\E\s*</span>|,
    html_minimal => qr|<span class="c[03]">\Q$var\E</span>|,
    html_subtle  => qr|<span class="(?:un)?covered">\Q$var\E</span>|,
    html_crisp   => qr|<span class="mcdc-pill [^"]*">\Q$var\E</span>|,
  );
  $re{$report}
}

my %Needs_template = (html_basic => 1, html_subtle => 1);

sub test_html_reports_note_limit () {
  my ($db, $path) = run_wide("too_wide_html", "$Narrow$Decl\n$Wide\n");
  for my $report (qw( html_basic html_minimal html_subtle html_crisp )) {
    subtest $report => sub {
      if ($Needs_template{$report} && !eval { require Template; 1 }) {
        Test::More::plan(skip_all => "Template not available");
        return;
      }
      my $outdir = "$db->{db}/$report";
      my $out    = `$^X -Iblib/lib -Iblib/arch bin/cover -report $report \\
        -silent -outputdir $outdir $db->{db} 2>&1`;
      is $? >> 8, 0, "cover -report $report exits 0";
      my $all = join "", map slurp($_), glob "$outdir/*.html";
      like $all, qr/too many conditions/, "$report notes the limit";
      like $all, pill_re($report, '$x'),
        "$report renders the narrow decision's pills";
      unlike $all, pill_re($report, '$v5'),
        "$report renders no atomic pill for the wide decision";
    };
  }
}

sub run_report ($db, $report) {
  my $out = `$^X -Iblib/lib -Iblib/arch bin/cover -report $report -silent \\
    $db->{db} 2>&1`;
  is $? >> 8, 0, "cover -report $report exits 0";
  $out
}

sub test_text_report_notes_limit () {
  my ($db, $path) = run_wide("too_wide_text", "$Narrow$Decl\n$Wide\n");
  my $out = run_report($db, "text");
  like $out, qr/\Qtoo many conditions\E/,
    "text report notes the limit in place of the missing list";
  unlike $out, qr/\$v1, \$v2/,
    "text report does not list the wide decision's conditions as missing";
}

sub test_compilation_report_notes_limit () {
  my ($db, $path) = run_wide("too_wide_comp", "$Narrow$Decl\n$Wide\n");
  my $out = run_report($db, "compilation");
  my $re = qr|Unanalysed MC/DC decision \(too many conditions\)|;
  like $out, qr/$re at .* line $Wide_line:/,
    "compilation report emits an unanalysed line";
  unlike $out, qr|Uncovered MC/DC pair \(\$v1|,
    "compilation report does not claim missing pairs for the wide decision";
}

# The JSON report carries the flag so consumers can distinguish "too wide
# to analyse" from "untested".  It is emitted only on unanalysed decisions,
# keeping existing output unchanged.
sub test_json_report_carries_flag () {
  subtest "json report" => sub {
    eval "require JSON::MaybeXS; 1" or do {
      Test::More::plan(skip_all => "JSON::MaybeXS not available");
      return;
    };
    my ($db, $path) = run_wide("too_wide_json", "$Narrow$Decl\n$Wide\n");
    my $outdir = "$db->{db}/json";
    my $out    = `$^X -Iblib/lib -Iblib/arch bin/cover -report json \\
      -silent -outputdir $outdir $db->{db} 2>&1`;
    is $? >> 8, 0, "cover -report json exits 0";

    my $json = JSON::MaybeXS->new(utf8 => 1)
      ->decode(slurp("$outdir/cover.json"));
    my ($f)  = grep { $_->{mcdc} } values $json->{files}->%*;
    ok $f, "json has a file with mcdc data";
    my @decisions = map { $_->@* } values $f->{mcdc}->%*;
    my ($wide)    = grep { $_->{covered}->@* == 18 } @decisions;
    my ($narrow)  = grep { $_->{covered}->@* == 2 } @decisions;
    ok $wide, "wide decision present in json";
    ok $wide->{unanalysed}, "wide decision flagged unanalysed in json";
    ok $narrow, "narrow decision present in json";
    ok !exists $narrow->{unanalysed},
      "narrow decision carries no unanalysed key";
  };
}

test_wide_decision_reported_unanalysed;
test_warning_respects_silent;
test_uncoverable_marker_ignored_with_warning;
test_text_report_notes_limit;
test_compilation_report_notes_limit;
test_html_reports_note_limit;
test_json_report_carries_flag;

done_testing;

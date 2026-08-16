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

use File::Spec ();
use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing like plan )];

BEGIN {
  plan skip_all => "CPAN::Meta required for this test"
    unless eval "require CPAN::Meta; 1";
}

sub write_file ($file, $contents) {
  open my $fh, ">", $file or die "write $file: $!";
  print $fh $contents;
  close $fh or die "close $file: $!";
}

sub setup ($tmpdir) {
  write_file(File::Spec->catfile($tmpdir, "MYMETA.json"), <<'JSON');
{
   "abstract" : "test distribution",
   "author" : [ "nobody" ],
   "dynamic_config" : 0,
   "generated_by" : "Devel::Cover tests",
   "license" : [ "perl_5" ],
   "meta-spec" : {
      "url" : "https://metacpan.org/pod/CPAN::Meta::Spec",
      "version" : 2
   },
   "name" : "Test-Dist",
   "release_status" : "stable",
   "version" : "0.01"
}
JSON

  my $script = File::Spec->catfile($tmpdir, "stdin.pl");
  write_file($script, <<'PERL');
BEGIN { close STDIN }
my $data = "-world-";
open STDIN, "<", \$data or die "open STDIN: $!";
my $line = <>;
print "got(", defined $line ? $line : "UNDEF", ")\n";
PERL
  $script
}

sub test_readline_with_mymeta () {
  my $tmpdir = tempdir(CLEANUP => 1);
  my $script = setup($tmpdir);

  my $db  = File::Spec->catdir($tmpdir, "cover_db");
  my $cmd = join " ", map qq("$_"), $^X, "-Mblib",
    "-MDevel::Cover=-silent,1,-db,$db,-dir,$tmpdir", $script;
  my $output = `$cmd 2>&1`;

  like $output, qr/\Qgot(-world-)\E/,
    "reading the distribution metadata leaves STDIN alone"
    or diag $output;
}

sub main () {
  test_readline_with_mymeta;
  done_testing;
}

main;

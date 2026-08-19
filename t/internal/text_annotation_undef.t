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

use File::Temp qw( tempdir );
use Test::More import => [qw( diag done_testing is like )];

use Devel::Cover::Report::Text ();

{

  package Test::Annotation::Empty;
  sub new    ($class)                  { bless {}, $class }
  sub count  ($self)                   { 2 }
  sub width  ($self, $i)               { 8 }
  sub header ($self, $i)               { "ann$i" }
  sub text   ($self, $file, $line, $i) { undef }
  sub error  ($self, $file, $line, $i) { 0 }
}

{

  package Mock::File;
  sub new ($class) { bless {}, $class }
}

{

  package Mock::Cover;
  sub new  ($class, $file) { bless { file => $file }, $class }
  sub file ($self, $name)  { $self->{file} }
}

{

  package Mock::DB;
  sub new            ($class, $cover) { bless { cover => $cover }, $class }
  sub cover          ($self)          { $self->{cover} }
  sub criteria       ($self)          { () }
  sub criteria_short ($self)          { () }
}

my $Dir = tempdir(CLEANUP => 1);

sub write_source () {
  my $file = "$Dir/source.pl";
  open my $fh, ">", $file or die "Can't open $file: $!";
  print $fh qq(my \$x = 1;\nmy \$y = 2;\nmy \$z = 3;\n);
  close $fh or die "Can't close $file: $!";
  $file
}

sub text_output ($file) {
  my $db      = Mock::DB->new(Mock::Cover->new(Mock::File->new));
  my $options = { show => {}, annotations => [Test::Annotation::Empty->new] };

  my $output;
  {
    open my $fh, ">", \$output or die "Cannot open scalar ref: $!";
    local *STDOUT = $fh;
    Devel::Cover::Report::Text::print_statement(
      $db, $file, $options, { $file => "source.pl" }
    );
    close $fh or die "Cannot close scalar ref: $!";
  }
  $output
}

sub test_missing_annotation_text_is_silent () {
  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_ };
  my $output = text_output(write_source);
  is @warnings, 0, "no warnings from missing annotation text"
    or diag join "", @warnings;
  like $output, qr/^line\s+err\s+ann0\s+ann1\b/m,
    "annotation headers still printed";
}

sub main () {
  test_missing_annotation_text_is_silent;
  done_testing;
}

main;

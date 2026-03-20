package Devel::Cover::Html_Common;

use strict;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use Exporter;

our @ISA       = "Exporter";
our @EXPORT_OK = qw( launch highlight $Have_highlighter );

our $Have_highlighter;
my ($Have_ppi, $Have_perltidy);

BEGIN {
  eval "use PPI; use PPI::HTML;";
  $Have_ppi = !$@;
  eval "use Perl::Tidy";
  $Have_perltidy    = !$@;
  $Have_highlighter = $Have_ppi || $Have_perltidy;
}

sub launch {
  my ($package, $opt) = @_;

  my $outfile = "$opt->{outputdir}/$opt->{option}{outputfile}";
  if (eval { require Browser::Open }) {
    Browser::Open::open_browser($outfile);
  } else {
    print STDERR "Devel::Cover: -launch requires Browser::Open\n";
  }
}

sub _highlight_ppi (@all_lines) {
  my $code      = join "", @all_lines;
  my $document  = PPI::Document->new(\$code);
  my $highlight = PPI::HTML->new(line_numbers => 1);
  my $pretty    = $highlight->html($document);

  my $split = qq(<span class="line_number">);

  no warnings "uninitialized";

  @all_lines = split /$split/, $pretty;
  for (@all_lines) {
    s{</span>( +)}{"</span>" . ("&nbsp;" x length $1)}e;
    $_ = "$split$_";
  }

  for (@all_lines) {
    s{<span class="line_number">.*?</span>}{};
    s{<span class="line_number">}{};
    s{<br>$}{};
    s{<br>\n</span>}{</span>};
  }

  shift @all_lines if $all_lines[0] eq "";
  @all_lines
}

sub _highlight_perltidy (@all_lines) {
  my @coloured;
  my ($stderr, $errorfile);
  Perl::Tidy::perltidy(
    source      => \@all_lines,
    destination => \@coloured,
    argv        => "-html -pre -nopod2html",
    stderr      => \$stderr,
    errorfile   => \$errorfile
  );
  shift @coloured;
  pop @coloured;
  @coloured = grep { !/<a name=/ } @coloured;
  @coloured
}

sub highlight ($option, @all_lines) {
  if ($Have_ppi && !$option->{noppihtml}) {
    return _highlight_ppi(@all_lines);
  } elsif ($Have_perltidy && !$option->{noperltidy}) {
    return _highlight_perltidy(@all_lines);
  }
  return;
}

=pod

=head1 NAME

Devel::Cover::Html_Common - Common code for HTML reporters

=head1 DESCRIPTION

This module provides common functionality for HTML reporters.

=head1 Functions

=over 4

=item launch

Launch a browser to view the report. HTML reporters just need to
import this function to enable the -launch flag for that report
type.

=item highlight ($option, @lines)

Syntax-highlight Perl source lines using PPI::HTML or Perl::Tidy,
whichever is available. Returns highlighted lines, or an empty list
if neither highlighter is installed. Pass the C<< $opt->{option} >>
hash so that C<noppihtml> and C<noperltidy> flags are respected.

=item $Have_highlighter

True if PPI::HTML or Perl::Tidy is available.

=back

=head1 SEE ALSO

Devel::Cover

=cut

1

package Devel::Cover::Html_Common;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use Exporter       qw( import );
use Digest::MD5    ();
use Encode         ();
use HTML::Entities ();

our @EXPORT_OK = qw(
  launch highlight $Have_highlighter
  coverage_class default_thresholds scar_class unique_filenames
  decode_guess escape_html source_layer
);

our $Have_highlighter;
my ($Have_ppi, $Have_perltidy);

BEGIN {
  eval "use PPI; use PPI::HTML;";
  $Have_ppi = !$@;
  eval "use Perl::Tidy";
  $Have_perltidy    = !$@;
  $Have_highlighter = $Have_ppi || $Have_perltidy;
}

sub default_thresholds () { { c0 => 75, c1 => 90, c2 => 100 } }

sub coverage_class ($pc, $t = undef) {
  $t //= default_thresholds;
  return "na" if !defined $pc || $pc eq "n/a";
  $pc < $t->{c0} ? "c0" : $pc < $t->{c1} ? "c1" : $pc < $t->{c2} ? "c2" : "c3"
}

sub scar_class ($scar) {
  return "" unless defined $scar;
  $scar < 16 ? "c3" : $scar < 34 ? "c2" : $scar < 41 ? "c1" : "c0"
}

sub unique_filenames (@files) {
  my (%name, %seen);
  for my $file (sort @files) {
    my $n = $file =~ s/\W/-/gr;
    if ($seen{$n}) {
      my $digest = Digest::MD5::md5_hex(Encode::encode_utf8($file));
      my $len    = 8;
      my $suffix = substr $digest, 0, $len;
      while ($seen{"$n--$suffix"}) {
        $suffix = substr $digest, 0, ++$len;
      }
      $n .= "--$suffix";
    }
    $seen{$n}++;
    $name{$file} = $n;
  }
  \%name
}

sub launch ($package, $opt) {
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

  my $split = '<span class="line_number">';

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

  shift @all_lines if @all_lines && $all_lines[0] eq "";
  pop @all_lines   if @all_lines && $all_lines[-1] eq "";
  @all_lines
}

sub _highlight_perltidy (@all_lines) {
  my @coloured;
  my ($stderr, $errorfile);
  Perl::Tidy::perltidy(
    source      => \@all_lines,
    destination => \@coloured,
    argv        => "-html -pre -nopod2html -npro",
    stderr      => \$stderr,
    errorfile   => \$errorfile,
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

sub decode_guess ($text) {
  return $text unless defined $text;
  my $chars = eval {
    Encode::decode("UTF-8", $text, Encode::FB_CROAK | Encode::LEAVE_SRC)
  };
  $chars //= eval { Encode::decode("iso-8859-1", $text) };
  $chars // $text
}

sub escape_html ($text) {
  # The characters that must be escaped in HTML text and attribute values
  state $unsafe = q(<>&"');
  HTML::Entities::encode_entities(decode_guess($text), $unsafe)
}

sub source_layer ($file) {
  open my $fh, "<", $file or return "";
  my $bytes = do { local $/; <$fh> };
  close $fh or return "";
  my $utf8 = defined $bytes && eval {
    Encode::decode("UTF-8", $bytes, Encode::FB_CROAK | Encode::LEAVE_SRC);
    1
  };
  $utf8 ? ":encoding(UTF-8)" : ":encoding(iso-8859-1)"
}

"
The sirens are screaming and the fires are howling
Way down in the valley tonight
"

__END__

=pod

=encoding utf8

=head1 NAME

Devel::Cover::Html_Common - Common code for HTML reporters

=head1 SYNOPSIS

  use Devel::Cover::Html_Common qw( launch highlight );

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

=item coverage_class ($percentage, $thresholds)

Map a coverage percentage to a CSS band name (C<c0>, C<c1>, C<c2> or
C<c3>). An undefined percentage or the string C<n/a> maps to C<na>. The
optional C<$thresholds> hashref carries C<c0>, C<c1> and C<c2> cut-off
points. It defaults to the values from C<default_thresholds> when omitted.

=item default_thresholds

Return a fresh hashref of the default band cut-off points (C<c0> 75,
C<c1> 90, C<c2> 100). A new copy is returned each call so callers may
mutate their own thresholds without affecting the defaults.

=item scar_class ($scar)

Map a SCAR value to a CSS band name (C<c0>, C<c1>, C<c2> or C<c3>), with
lower values in the better bands. An undefined value maps to the empty
string.

=item unique_filenames (@files)

Map each source path to a unique page name, returned as a hashref. Each
name reduces every non-word character to a hyphen, as the reports have
always done. That mapping is many-to-one, so distinct paths such as
C<X/Y.pm> and C<X-Y.pm> can produce the same name. When two paths
collide, the sorted-first path keeps the plain name and each later
collider is given a stable suffix of C<--> plus the leading hex
characters of the MD5 of its path. Non-colliding paths are unchanged.

=item decode_guess ($text)

Return C<$text> as a character string. Covered source files carry no
encoding declaration the reports could trust, so this guesses. The bytes
are decoded as strict UTF-8 when they form a valid sequence and as
Latin-1 when they do not, a guess that cannot fail. A string that
already contains wide characters is returned unchanged, since both
decodes refuse it. Undefined input is returned unchanged.

=item escape_html ($text)

Return C<$text> decoded via C<decode_guess> with the HTML-unsafe
characters C<< < > & " ' >> escaped as entities. Other characters,
including non-ASCII ones, are left alone so that UTF-8 output renders
them directly.

=item source_layer ($file)

Return the I/O layer with which to read the source file C<$file>, using
the same guess as C<decode_guess>. An unreadable file yields an empty
string so the caller's own open reports the error.

=back

=head1 SEE ALSO

Devel::Cover

=cut

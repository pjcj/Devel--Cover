package TestHelper;

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use v5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Exporter qw( import );
our @EXPORT_OK = qw( create_cover_db run_cover setup_lib_dir );

use Cwd            qw( realpath );
use File::Basename qw( dirname );
use File::Path     qw( make_path );
use File::Spec     ();
use File::Temp     qw( tempdir );

my $Root  = realpath(File::Spec->catdir(dirname(__FILE__), "..", ".."));
my $Cover = File::Spec->catfile($Root, "bin", "cover");

sub run_cover (@args) {
  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};
  my $cmd = join " ", "$^X -Iblib/lib -Iblib/arch", $Cover, @args;
  my $out = `$cmd 2>&1`;
  ($out, $? >> 8)
}

sub _write_module ($path, $pkg, $body) {
  my $dir = dirname($path);
  make_path($dir) unless -d $dir;
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh "package $pkg;\nuse strict;\nuse warnings;\n\n$body\n1\n";
  close $fh or die "Cannot close $path: $!"
}

# Shared module bodies - identical between Covered and Uncovered
# variants so criteria counts match exactly for comparison.

my $Calc_body = <<'BODY';
=head2 add

Add two numbers and classify the result.

=cut

sub add {
  my ($a, $b) = @_;
  my $sum = $a + $b;
  if ($sum > 100) {
    return "big";
  } elsif ($sum > 0) {
    return "positive";
  } else {
    return "non-positive";
  }
}

sub check {
  my ($x, $y) = @_;
  my $ok = $x && $y;
  return $ok || "invalid";
}

sub negate {
  my $x = shift;
  return -$x;
}
BODY

my $Full_body = <<'BODY';
=head2 double

Double a number.

=cut

sub double {
  my $x = shift;
  if ($x > 0) {
    return $x * 2;
  } else {
    return 0;
  }
}

=head2 clamp

Clamp a value to a range.

=cut

sub clamp {
  my ($val, $min, $max) = @_;
  if ($val < $min) {
    return $min;
  } elsif ($val > $max) {
    return $max;
  } else {
    return $val;
  }
}

=head2 sign

Return the sign of a number.

=cut

sub sign {
  my $x = shift;
  return $x > 0 ? "positive" : "non-positive";
}

=head2 label

Label a value.

=cut

sub label {
  my $val = shift;
  return $val && "yes" || "no";
}

=head2 abs_val

Absolute value.

=cut

sub abs_val {
  my $x = shift;
  return $x < 0 ? -$x : $x;
}

=head2 is_even

Check if even.

=cut

sub is_even {
  my $x = shift;
  return $x % 2 == 0;
}

=head2 inc

Increment.

=cut

sub inc {
  my $x = shift;
  return $x + 1;
}

sub _helper {
  my $x = shift;
  return $x + 1;
}
BODY

my $Trivial_body = <<'BODY';
=head2 id

Return the argument unchanged.

=cut

sub id {
  my $x = shift;
  return $x;
}
BODY

my $Utils_body = <<'BODY';
=head2 greet

Return a greeting string.

=cut

sub greet {
  my $name = shift;
  return "hello $name";
}

sub upper {
  my $str = shift;
  return uc($str) if defined $str;
  return "";
}
BODY

sub setup_lib_dir () {
  my $tmpdir = realpath(tempdir(CLEANUP => 1));
  my $libdir = File::Spec->catdir($tmpdir, "lib");

  for my $side (qw( Covered Uncovered )) {
    _write_module(
      File::Spec->catfile($libdir, $side, "Calc.pm"), "${side}::Calc",
      $Calc_body
    );
    _write_module(
      File::Spec->catfile($libdir, $side, "Full.pm"), "${side}::Full",
      $Full_body
    );
    _write_module(
      File::Spec->catfile($libdir, $side, "Trivial.pm"), "${side}::Trivial",
      $Trivial_body
    );
    _write_module(
      File::Spec->catfile($libdir, $side, "Utils.pm"), "${side}::Utils",
      $Utils_body
    );
  }

  # blib subdir - should be excluded by scan_select_dirs
  my $blib = File::Spec->catdir($libdir, "blib", "lib");
  make_path($blib);
  _write_module(
    File::Spec->catfile($blib, "BlibMod.pm"),
    "BlibMod", "sub x { 1 }\n"
  );

  # non-pm file - should be excluded
  open my $fh, ">", File::Spec->catfile($libdir, "README.txt")
    or die "Cannot create README: $!";
  close $fh or die $!;

  ($tmpdir, $libdir)
}

sub create_cover_db ($tmpdir, $libdir) {
  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  my $select   = "\\Q$libdir\\E";

  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};

  my $oneliner = join " ", "use Covered::Calc; use Covered::Full;",
    "use Covered::Trivial; use Covered::Utils;", "Covered::Calc::add(1, 2);",
    "Covered::Utils::greet(q(world));", "Covered::Utils::upper(q(hi));",
    "Covered::Full::double(5);",        "Covered::Full::double(-1);",
    "Covered::Full::clamp(0, 1, 10);",  "Covered::Full::clamp(5, 1, 10);",
    "Covered::Full::clamp(99, 1, 10);", "Covered::Full::sign(1);",
    "Covered::Full::sign(-1);",         "Covered::Full::label(1);",
    "Covered::Full::label(0);",         "Covered::Full::abs_val(-3);",
    "Covered::Full::is_even(4);",       "Covered::Full::inc(1);",
    "Covered::Trivial::id(42)";
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$libdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0,-select,$select"
    . qq[ -e "$oneliner" 2>&1];
  my $out = `$cmd`;
  die "Failed to create cover_db:\n$out\n" if $?;

  $cover_db
}

1

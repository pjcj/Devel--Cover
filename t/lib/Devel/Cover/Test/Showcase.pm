package Devel::Cover::Test::Showcase;

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Exporter qw( import );
our @EXPORT_OK = qw( create_cover_db run_cover setup_lib_dir slurp );

use Cwd            qw( realpath );
use File::Basename qw( dirname );
use File::Path     qw( make_path );
use File::Spec     ();
use File::Temp     qw( tempdir );

my $Root  = realpath(File::Spec->catdir(dirname(__FILE__), (("..") x 5)));
my $Cover = File::Spec->catfile($Root, "bin", "cover");

sub slurp ($path) {
  open my $fh, "<", $path or die "Cannot read $path: $!";
  my $content = do { local $/; <$fh> };
  close $fh or die "Cannot close $path: $!";
  $content
}

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

my $Calc_body = <<'BODY' =~ s/^  //gmr;
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

my $Full_body = <<'BODY' =~ s/^  //gmr;
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

my $Logic_body = <<'BODY' =~ s/^  //gmr;
  =head2 grant

  Decide whether access is granted.

  =cut

  sub grant {
    my ($owner, $unlocked, $admin) = @_;
    my $ok = ($owner && $unlocked) || $admin;
    return $ok;
  }

  =head2 reuse

  A decision reusing a condition on both sides.

  =cut

  sub reuse {
    my ($a, $b, $c) = @_;
    my $r = ($a && $b) || ($a && $c);
    return $r;
  }

  =head2 pick

  Return the first defined value, or a default.

  =cut

  sub pick {
    my ($primary, $backup) = @_;
    my $v = $primary // $backup // "none";
    return $v;
  }

  sub either {
    my ($a, $b) = @_;
    my $x = ($a xor $b);
    return $x;
  }

  sub any_flag {
    my @f = @_;
    my $any
      = $f[0] || $f[1] || $f[2]  || $f[3]  || $f[4]  || $f[5]  || $f[6]
      || $f[7] || $f[8] || $f[9] || $f[10] || $f[11] || $f[12] || $f[13]
      || $f[14] || $f[15] || $f[16];
    return $any;
  }

  sub find {
    my ($target, @items) = @_;
    my $found;
    for my $item (@items) {
      next unless defined $item;
      if ($item eq $target) {
        $found = $item;
        last;
      }
    }
    return $found;
  }
BODY

my $Markers_body = <<'BODY' =~ s/^  //gmr;
  =head2 fetch

  Fetch a cached value, populating the default on first use.

  =cut

  sub fetch {
    my ($cache, $key, $default) = @_;
    # uncoverable mcdc
    return $cache->{$key} //= $default;
  }

  =head2 audit

  Record a value, guarding against an impossible state.

  =cut

  sub audit {
    my ($value) = @_;
    my $active = 1;
    # uncoverable condition left
    # uncoverable mcdc pair:1
    my $ok = $active && $value;
    # uncoverable branch true
    if (!$active) {
      # uncoverable statement
      die "audit while inactive";
    }
    return $ok;
  }

  sub emergency_stop {
    # uncoverable subroutine
    # uncoverable statement
    die "emergency stop";
  }
BODY

my $Trivial_body = <<'BODY' =~ s/^  //gmr;
  =head2 id

  Return the argument unchanged.

  =cut

  sub id {
    my $x = shift;
    return $x;
  }
BODY

my $Utils_body = <<'BODY' =~ s/^  //gmr;
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
      $Calc_body,
    );
    _write_module(
      File::Spec->catfile($libdir, $side, "Full.pm"), "${side}::Full",
      $Full_body,
    );
    _write_module(
      File::Spec->catfile($libdir, $side, "Logic.pm"), "${side}::Logic",
      $Logic_body,
    );
    _write_module(
      File::Spec->catfile($libdir, $side, "Markers.pm"), "${side}::Markers",
      $Markers_body,
    );
    _write_module(
      File::Spec->catfile($libdir, $side, "Trivial.pm"), "${side}::Trivial",
      $Trivial_body,
    );
    _write_module(
      File::Spec->catfile($libdir, $side, "Utils.pm"), "${side}::Utils",
      $Utils_body,
    );
  }

  # blib subdir - should be excluded by scan_select_dirs
  my $blib = File::Spec->catdir($libdir, "blib", "lib");
  make_path($blib);
  _write_module(
    File::Spec->catfile($blib, "BlibMod.pm"),
    "BlibMod", "sub x { 1 }\n",
  );

  # non-pm file - should be excluded
  open my $fh, ">", File::Spec->catfile($libdir, "README.txt")
    or die "Cannot create README: $!";
  close $fh or die $!;

  ($tmpdir, $libdir)
}

sub create_cover_db ($tmpdir, $libdir) {
  my $cover_db = File::Spec->catdir($tmpdir, "cover_db");
  # quotemeta escapes the path for use as a regex in Devel::Cover's -select
  # option.  On Windows, the -M argument passes through Perl's '' processing
  # which halves \\ to \, stripping the escaping that quotemeta added for
  # backslash path separators.  Pre-doubling the backslashes with s|\\|\\\\|g
  # compensates so the regex arrives intact.
  my $select = quotemeta $libdir;
  $select =~ s|\\|\\\\|g if $^O eq "MSWin32";

  local $ENV{DEVEL_COVER_SELF};
  delete $ENV{DEVEL_COVER_SELF};

  my $oneliner = join " ", split /\n/, <<ONELINER =~ s/^  //gmr;
  use Covered::Calc;
  use Covered::Full;
  use Covered::Logic;
  use Covered::Markers;
  use Covered::Trivial;
  use Covered::Utils;
  Covered::Calc::add(1, 2);
  Covered::Logic::grant(1, 1, 0);
  Covered::Logic::grant(0, 0, 1);
  Covered::Logic::grant(0, 0, 0);
  Covered::Logic::reuse(1, 1, 0);
  Covered::Logic::reuse(1, 0, 1);
  Covered::Logic::reuse(0, 0, 0);
  Covered::Logic::pick(undef, q(backup));
  Covered::Logic::pick(q(main), q(backup));
  Covered::Logic::either(1, 0);
  Covered::Logic::any_flag(1);
  Covered::Logic::any_flag(0, 0, 1);
  Covered::Logic::find(q(b), q(a), undef, q(b));
  my %c;
  Covered::Markers::fetch(\\%c, q(k), 1);
  Covered::Markers::fetch(\\%c, q(k), 2);
  Covered::Markers::audit(1);
  Covered::Markers::audit(0);
  Covered::Utils::greet(q(world));
  Covered::Utils::upper(q(hi));
  Covered::Full::double(5);
  Covered::Full::double(-1);
  Covered::Full::clamp(0, 1, 10);
  Covered::Full::clamp(5, 1, 10);
  Covered::Full::clamp(99, 1, 10);
  Covered::Full::sign(1);
  Covered::Full::sign(-1);
  Covered::Full::label(1);
  Covered::Full::label(0);
  Covered::Full::abs_val(-3);
  Covered::Full::is_even(4);
  Covered::Full::inc(1);
  Covered::Trivial::id(42)
ONELINER
  my $cmd
    = "$^X -Iblib/lib -Iblib/arch -I$libdir"
    . " -MDevel::Cover=-db,$cover_db,-silent,1,-merge,0,-select,$select"
    . qq( -e "$oneliner" 2>&1);
  my $out = `$cmd`;
  die "Failed to create cover_db:\n$out\n" if $?;

  $cover_db
}

"
Would you do it with me?
Heal the scars and change the stars
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Test::Showcase - fixture library for Devel::Cover showcase

=head1 SYNOPSIS

 use Devel::Cover::Test::Showcase qw(
   setup_lib_dir create_cover_db run_cover slurp
 );

 my ($tmpdir, $libdir) = setup_lib_dir;
 my $cover_db          = create_cover_db($tmpdir, $libdir);
 my ($out, $exit)      = run_cover(
   "--select_dir", $libdir,
   "--report",     "text",
   "--silent",
   $cover_db,
 );

=head1 DESCRIPTION

This module provides a reusable set of Perl source fixtures and helper functions
for showcasing and testing Devel::Cover features.  It is used by the
C<utils/showcase> script (via C<make showcase_*> targets) and by the internal
test suite.

L</setup_lib_dir> creates a temporary directory tree containing twelve small
modules - six under C<Covered::> and six identical copies under C<Uncovered::>
- that exercise a range of coverage criteria: statements, branches
(if/elsif/else, ternary, postfix, loop control), conditions (C<&&>, C<||>,
C<//>, C<xor>), MC/DC (compound, coupled and too-wide decisions), uncoverable
markers, subroutines, and pod.

L</create_cover_db> runs the C<Covered::> modules under Devel::Cover to produce
a coverage database.  The C<Uncovered::> modules are never loaded, so they
appear as untested files when C<--select_dir> is used.

=head1 EXPORTED SUBROUTINES

All functions are exported on request via L<Exporter>.

=head2 setup_lib_dir

 my ($tmpdir, $libdir) = setup_lib_dir;

Create a temporary directory tree containing twelve fixture modules: six under
C<Covered::> and six identical copies under C<Uncovered::>.  Also creates a
C<blib/lib/BlibMod.pm> (to test blib exclusion) and a C<README.txt> (to test
non-Perl file exclusion).

Returns C<($tmpdir, $libdir)>.  The tempdir is cleaned up automatically when
C<$tmpdir> goes out of scope.

=head2 create_cover_db

 my $cover_db = create_cover_db($tmpdir, $libdir);

Collect coverage on the C<Covered::> modules by exercising a representative set
of calls, and return the path to the resulting C<cover_db> directory. C<$tmpdir>
and C<$libdir> should be the values returned by L</setup_lib_dir>.

Only the C<Covered::> side is exercised; the C<Uncovered::> modules are never
loaded, so they appear as untested files when C<--select_dir> is used.

=head2 run_cover

 my ($output, $exit_code) = run_cover(@args);

Run C<bin/cover> with the given arguments, using the current C<$^X> and the blib
paths so that the development version of Devel::Cover is
used. C<DEVEL_COVER_SELF> is temporarily cleared to avoid self-coverage
interference.

=head2 slurp

 my $content = slurp($path);

Read and return the entire contents of the file at C<$path>.

=head1 FIXTURE MODULES

The following modules are created in both the C<Covered::> and C<Uncovered::>
namespaces, with identical source:

=over

=item B<Calc> - if/elsif/else branches, C<&&>/C<||> conditions, pod

=item B<Full> - branches, ternaries, conditions, nine subs (including a private
C<_helper>), full pod coverage

=item B<Logic> - MC/DC decisions: a compound decision, a coupled decision
reusing a condition on both sides, chained C<//> with a constant default,
C<xor>, a 17-condition decision too wide to analyse, and a loop with postfix
C<unless> and C<last>

=item B<Markers> - uncoverable markers for statement, branch, condition,
subroutine and mcdc (bare and C<pair:N>), so excused entries show in every
reporter

=item B<Trivial> - single sub, no branches or conditions

=item B<Utils> - string functions, postfix C<if> branch, partial pod

=back

=head1 LICENCE

Copyright 2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

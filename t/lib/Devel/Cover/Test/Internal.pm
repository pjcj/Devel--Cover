package Devel::Cover::Test::Internal;

# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

use Exporter qw( import );
our @EXPORT_OK
  = qw( parse_comments run_under_cover warnings_from write_script );

use Cwd        qw( abs_path );
use File::Spec ();
use File::Temp qw( tempdir );

use Devel::Cover::DB ();

# One tempdir per process; per-call labels keep coverage db paths distinct.
my $Tmpdir = tempdir(CLEANUP => 1);

sub write_script ($name, $content) {
  my $path = File::Spec->catfile($Tmpdir, $name);
  open my $fh, ">", $path or die "Cannot write $path: $!";
  print $fh $content;
  close $fh or die "Cannot close $path: $!";
  $path
}

{
  no feature "signatures";

  sub warnings_from (&) {
    my ($code) = @_;
    my $err = "";
    open my $save_err, ">&", \*STDERR or die "Cannot dup STDERR: $!";
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">", \$err or die "Cannot redirect STDERR: $!";
    $code->();
    close STDERR or die "Cannot close STDERR: $!";
    open STDERR, ">&", $save_err or die "Cannot restore STDERR: $!";
    [split /(?<=\n)/, $err]
  }
}

sub parse_comments ($source) {
  my $path     = write_script("source.pl", $source);
  my $unc      = {};
  my $warnings = warnings_from {
    Devel::Cover::DB->new->uncoverable_comments($unc, $path, "digest");
  };
  ($unc, $warnings, $path)
}

sub run_under_cover ($script, $label, %opts) {
  my $cover_db = File::Spec->catdir($Tmpdir, "cover_db_$label");
  my @criteria = ($opts{criteria} // [])->@*;
  my @parts    = ("-db,$cover_db", "-silent,1");
  push @parts, join ",", "-coverage", @criteria if @criteria;
  push @parts, ($opts{options} // [])->@*;
  push @parts, "+select," . abs_path($Tmpdir);
  my @cmd = (
    $^X, "-Iblib/lib", "-Iblib/arch", "-MDevel::Cover=" . join(",", @parts),
    $script,
  );
  system(@cmd) == 0 or die "Failed to run script under Devel::Cover: @cmd";

  my $db = Devel::Cover::DB->new(db => $cover_db);
  $db->merge_runs;
  ($db, abs_path($script))
}

"
Well, the dogs were barking at the new moon
Whistling a new tune
Hoping it would come soon
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Test::Internal - run generated scripts under Devel::Cover

=head1 SYNOPSIS

 use Devel::Cover::Test::Internal qw( write_script run_under_cover );

 my $script = write_script("simple_and.pl", $source);
 my ($db, $path) = run_under_cover(
   $script, "simple_and",
   criteria => ["condition", "mcdc"],
 );
 my $cover = $db->cover;

=head1 DESCRIPTION

Shared helpers for internal tests that write a small Perl script, run it
under Devel::Cover in a child process, and inspect the resulting coverage
database.  The module owns one temporary directory per process; each call
uses its label to keep coverage db paths distinct, and the directory is
cleaned up automatically at process exit.

=head1 EXPORTED SUBROUTINES

All functions are exported on request via L<Exporter>.

=head2 write_script ($name, $content)

 my $script = write_script("simple_and.pl", $source);

Write C<$content> to a file called C<$name> in the shared temporary
directory and return its path.

=head2 warnings_from ($code)

 my $warnings = warnings_from { $db->cover };

Run C<$code> with STDERR captured and return an arrayref of the lines it
wrote, keeping their trailing newlines.

=head2 parse_comments ($source)

 my ($unc, $warnings, $path) = parse_comments($source);

Write C<$source> to a file, parse its uncoverable comments with
L<Devel::Cover::DB/uncoverable_comments> under C<warnings_from>, and return
the uncoverable data (keyed by the digest C<"digest">), the captured
warnings and the file's path.

=head2 run_under_cover ($script, $label, %opts)

 my ($db, $path) = run_under_cover($script, $label, %opts);

Run C<$script> under Devel::Cover with C<-silent,1>, collecting into a
coverage db named after C<$label>, and die if the child fails.  Options:

=over

=item C<criteria>

Arrayref of coverage criteria, e.g. C<["condition", "mcdc"]>, passed as a
single C<-coverage> option.  Omit to collect the default set (all criteria).

=item C<options>

Arrayref of extra Devel::Cover option strings, e.g. C<["-replace_ops,0"]>,
inserted before the C<+select> of the shared temporary directory.

=back

Returns the loaded, run-merged L<Devel::Cover::DB> and the absolute
symlink-resolved path of C<$script> (the path Devel::Cover stores for it).
Repeated calls with the same C<$label> accumulate runs in the same
coverage db.

=head1 LICENCE

Copyright 2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

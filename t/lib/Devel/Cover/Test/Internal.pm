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
our @EXPORT_OK = qw( write_script run_under_cover );

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

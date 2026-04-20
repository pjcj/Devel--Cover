# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Log;

use 5.20.0;
use warnings;
use feature qw( postderef signatures );
no warnings qw( experimental::postderef experimental::signatures );

our $VERSION;

use Devel::Cover::Inc ();
use Exporter          qw( import );

BEGIN { $VERSION //= $Devel::Cover::Inc::VERSION }

our @EXPORT_OK = qw( dcinfo dcerror dcprogress );
our $Prefix    = "cover";

sub dcinfo ($msg) {
  return if $Devel::Cover::Silent;
  print STDERR "$Prefix: $msg\n";
}

sub dcerror ($msg) {
  print STDERR "$Prefix: $msg\n";
}

sub dcprogress ($msg) {
  return if $Devel::Cover::Silent;
  print STDERR "$Prefix: $msg\n";
}

1;

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Log - Centralised diagnostic output for Devel::Cover

=head1 SYNOPSIS

 use Devel::Cover::Log qw( dcinfo dcerror dcprogress );

 dcinfo "Reading database from $dbname";
 dcerror "Unrecognised output format: $fmt";
 dcprogress "Rendering $n of $total";

 # Tools other than C<cover> can override the prefix:
 local $Devel::Cover::Log::Prefix = "gcov2perl";
 dcinfo "Writing coverage database to $db";

=head1 DESCRIPTION

All diagnostic output goes to STDERR with a consistent C<"$Prefix: "> prefix
(default C<cover>).  STDOUT is reserved for requested output such as the
summary table, the C<--dump_db> dump, and report content for text-based
reporters.

Functions are exported on request; import only those you need.

=head2 Functions

=over 4

=item dcinfo($msg)

Informational/progress/status message.  Silenced when
C<$Devel::Cover::Silent> is true.

=item dcerror($msg)

Error message.  Never silenced: errors are always reported.

=item dcprogress($msg)

Reserved for progress reporting.  Currently behaves like C<dcinfo>; future
versions may add tty-aware line-overwrite behaviour.  Silenced when
C<$Devel::Cover::Silent> is true.

=back

=head1 SEE ALSO

L<Devel::Cover>

=head1 LICENCE

Copyright 2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

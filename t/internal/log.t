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

use Test::More import => [qw( done_testing is )];

use Devel::Cover::Log qw( dcerror dcinfo dcprogress );

{
  no feature "signatures";

  sub capture (&) {
    my ($code) = @_;
    my ($out, $err) = ("", "");
    open my $save_out, ">&", \*STDOUT or die "Cannot dup STDOUT: $!";
    open my $save_err, ">&", \*STDERR or die "Cannot dup STDERR: $!";
    close STDOUT or die "Cannot close STDOUT: $!";
    close STDERR or die "Cannot close STDERR: $!";
    open STDOUT, ">", \$out or die "Cannot redirect STDOUT: $!";
    open STDERR, ">", \$err or die "Cannot redirect STDERR: $!";
    $code->();
    close STDOUT or die "Cannot close STDOUT: $!";
    close STDERR or die "Cannot close STDERR: $!";
    open STDOUT, ">&", $save_out or die "Cannot restore STDOUT: $!";
    open STDERR, ">&", $save_err or die "Cannot restore STDERR: $!";
    ($out, $err)
  }
}

sub test_dcinfo_writes_to_stderr () {
  local $Devel::Cover::Silent = 0;
  my ($out, $err) = capture { dcinfo "hello" };
  is $out, "",               "dcinfo: nothing on STDOUT";
  is $err, "cover: hello\n", "dcinfo: prefixed message on STDERR";
}

sub test_dcinfo_silenced () {
  local $Devel::Cover::Silent = 1;
  my ($out, $err) = capture { dcinfo "hello" };
  is $out, "", "dcinfo silent: nothing on STDOUT";
  is $err, "", "dcinfo silent: nothing on STDERR";
}

sub test_dcerror_writes_to_stderr () {
  local $Devel::Cover::Silent = 0;
  my ($out, $err) = capture { dcerror "oops" };
  is $out, "",              "dcerror: nothing on STDOUT";
  is $err, "cover: oops\n", "dcerror: prefixed message on STDERR";
}

sub test_dcerror_not_silenced () {
  local $Devel::Cover::Silent = 1;
  my ($out, $err) = capture { dcerror "oops" };
  is $out, "",              "dcerror silent: nothing on STDOUT";
  is $err, "cover: oops\n", "dcerror silent: still emitted - not guarded";
}

sub test_dcprogress_writes_to_stderr () {
  local $Devel::Cover::Silent = 0;
  my ($out, $err) = capture { dcprogress "step 1" };
  is $out, "",                "dcprogress: nothing on STDOUT";
  is $err, "cover: step 1\n", "dcprogress: prefixed message on STDERR";
}

sub test_dcprogress_silenced () {
  local $Devel::Cover::Silent = 1;
  my ($out, $err) = capture { dcprogress "step 1" };
  is $out, "", "dcprogress silent: nothing on STDOUT";
  is $err, "", "dcprogress silent: nothing on STDERR";
}

sub test_prefix_override () {
  local $Devel::Cover::Silent      = 0;
  local $Devel::Cover::Log::Prefix = "gcov2perl";
  my ($out, $err) = capture { dcinfo "writing" };
  is $out, "",                     "prefix override: nothing on STDOUT";
  is $err, "gcov2perl: writing\n", "prefix override: custom prefix used";
}

sub test_prefix_override_error () {
  local $Devel::Cover::Silent      = 0;
  local $Devel::Cover::Log::Prefix = "gcov2perl";
  my ($out, $err) = capture { dcerror "bad" };
  is $err, "gcov2perl: bad\n", "prefix override: dcerror uses custom prefix";
}

sub test_multiline_message () {
  local $Devel::Cover::Silent = 0;
  my ($out, $err) = capture { dcinfo "line 1\nline 2" };
  is $err, "cover: line 1\nline 2\n",
    "multiline: body preserved verbatim, single trailing newline added";
}

test_dcinfo_writes_to_stderr;
test_dcinfo_silenced;
test_dcerror_writes_to_stderr;
test_dcerror_not_silenced;
test_dcprogress_writes_to_stderr;
test_dcprogress_silenced;
test_prefix_override;
test_prefix_override_error;
test_multiline_message;

done_testing;

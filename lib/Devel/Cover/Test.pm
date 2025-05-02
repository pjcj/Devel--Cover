# Copyright 2002-2025, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Test;

use strict;
use warnings;

# VERSION

use Carp;

use File::Spec;
use Test::More;

use Devel::Cover::Inc;

my $LATEST_RELEASED_PERL = 40;

sub new {
  my $class = shift;
  my $test  = shift;
  croak "No test specified" unless $test;
  my %params = @_;

  my $criteria
    = delete $params{criteria} || "statement branch condition subroutine";

  eval "use Test::Differences";
  my $differences = $INC{"Test/Differences.pm"};

  my $self = bless {
    test             => $test,
    criteria         => [$criteria],
    skip             => "",
    uncoverable_file => [],
    select           => "",
    ignore           => [],
    changes          => [],
    test_parameters  => [],
    debug            => $ENV{DEVEL_COVER_DEBUG} || 0,
    differences      => $differences,
    no_coverage      => $ENV{DEVEL_COVER_NO_COVERAGE} || 0,
    delay_after_run  => 0,
    %params,
  }, $class;

  $self->get_params
}

sub set_test {
  my $self = shift;
  my ($test) = @_;
  $self->{test} = $test;
}

sub shell_quote {
  my ($item) = @_;
  $^O eq "MSWin32" ? (/ / and $_ = qq("$_")) : s/ /\\ /g for $item;
  $item
}

sub get_params {
  my $self = shift;

  my $test = $self->test_file;
  if (open my $fh, "<", $test) {
    while (<$fh>) {
      push @{ $self->{$1} }, $2 if /__COVER__\s+(\w+)\s+(.*)/;
    }
    close $fh or die "Cannot close $test: $!";
  }

  $self->{criteria} = $self->{criteria}[-1];
  $self->{select} ||= "-select /tests/$self->{test}\\b";
  $self->{test_parameters}
    = "$self->{select}"
    . " -ignore blib Devel/Cover @{$self->{ignore}}"
    . " -merge 0 -coverage $self->{criteria} "
    . "@{$self->{test_parameters}}";
  $self->{criteria} =~ s/-\w+//g;
  $self->{db_name} ||= $self->{test};
  $self->{cover_db} = "./t/e2e/cover_db_$self->{db_name}/";
  unless (mkdir $self->{cover_db}) {
    die "Can't mkdir $self->{cover_db}: $!" unless -d $self->{cover_db};
  }
  my $p = $self->{cover_parameters} || [];
  $self->{cover_parameters}
    = join(" ", map "-coverage $_", split " ", $self->{criteria})
    . " @$p -report text "
    . shell_quote $self->{cover_db};
  $self->{cover_parameters}
    .= " -uncoverable_file " . "@{$self->{uncoverable_file}}"
    if @{ $self->{uncoverable_file} };
  if (exists $self->{skip_test}) {
    for my $s (@{ $self->{skip_test} }) {
      my $r = shift @{ $self->{skip_reason} };
      next unless eval "{$s}";
      $self->{skip} = $r;
      last;
    }
  }

  $self
}

sub perl {
  my $self = shift;
  join " ", map shell_quote($_), $Devel::Cover::Inc::Perl, map "-I./$_", "",
    "blib/lib", "blib/arch"
}

sub test_command {
  my $self = shift;

  my $c = $self->perl;
  unless ($self->{no_coverage}) {
    $c
      .= " "
      . shell_quote "-MDevel::Cover="
      . join(",", "-db", $self->{cover_db}, split " ",
        $self->{test_parameters});
  }
  $c .= " " . shell_quote $self->test_file;
  $c .= " " . $self->test_file_parameters;

  $c
}

sub cover_command {
  my $self = shift;
  my $c    = $self->perl . " ./bin/cover $self->{cover_parameters}";
  $c
}

sub test_file {
  my $self = shift;
  "./tests/$self->{test}"
}

sub test_file_parameters {
  my $self = shift;
  exists $self->{test_file_parameters} ? $self->{test_file_parameters} : ""
}

sub _get_right_version {
  my ($td, $test) = @_;
  opendir D, $td or die "Can't opendir $td: $!";
  my @versions
    = sort { $a <=> $b } map { /^$test\.(5\.\d+)$/ ? $1 : () } readdir D;
  closedir D or die "Can't closedir $td: $!";
  # print STDERR "Versions for [$test] from [$td] @versions\n";
  my $v = "5.0";
  for (@versions) {
    last if $_ > $];
    $v = $_;
  }
  # die "Can't find golden results for $test" if $v eq "5.0";
  $v
}

sub cover_gold {
  my $self = shift;
  my $td   = "./test_output/cover";
  my $test = $self->{golden_test} || $self->{test};
  my $v
    = exists $ENV{DEVEL_COVER_GOLDEN_VERSION}
    ? $ENV{DEVEL_COVER_GOLDEN_VERSION}
    : _get_right_version($td, $test);
  ("$td/$test", $v eq "5.0" ? 0 : $v)
}

sub run_command {
  my $self = shift;
  my ($command) = @_;

  print STDERR "Running test [$command]\n" if $self->{debug};

  open my $fh, "-|", "$command 2>&1" or die "Cannot run $command: $!";
  my @lines;
  while (<$fh>) {
    push @lines, $_;
    print STDERR if $self->{debug};
  }
  if (!close $fh) {
    die "Cannot close $command: $!" if $!;
    die "Error closing $command, output was:\n", @lines;
  }

  if ($self->{delay_after_run}) {
    eval { select undef, undef, undef, $self->{delay_after_run}; 1 }
      or sleep int $self->{delay_after_run} + 1;
  }

  1
}

sub run_test {
  my $self = shift;

  $ENV{DEVEL_COVER_TEST_SUITE} = 1;

  if ($self->{skip}) {
    plan skip_all => $self->{skip};
    return;
  }

  my $version = int(($] - 5) * 1000 + 0.5);
  if ($version % 2 && $version < $LATEST_RELEASED_PERL) {
    plan skip_all => "Perl version $] is an obsolete development version";
    return;
  }

  my ($base, $v) = $self->cover_gold;
  # print STDERR "[$base,$v]\n";
  return 1 unless $v;  # assume we are generating the golden results
  my $gold = "$base.$v";

  open my $i, "<", $gold or die "Cannot open $gold: $!";
  my @cover = <$i>;
  close $i or die "Cannot close $gold: $!";
  $self->{cover} = \@cover;

  # print STDERR "gold from $gold\n", @cover if $self->{debug};

  plan tests => $self->{differences} ? 1
    : exists $self->{tests} ? $self->{tests}->(scalar @cover)
    :                         scalar @cover;

  local $ENV{PERL5OPT};
  $self->{run_test}
    ? $self->{run_test}->($self)
    : $self->run_command($self->test_command);
  $self->run_cover unless $self->{no_report};
  $self->{end}->() if $self->{end};

  1
}

sub run_cover {
  my $self = shift;

  my $cover_com = $self->cover_command;
  print STDERR "Running cover [$cover_com]\n" if $self->{debug};

  my (@at, @ac);
  my $change_line = sub {
    my ($get_line) = @_;
    local *_;
    LOOP: while (1) {
      $_ = scalar $get_line->();
      $_ = "" unless defined $_;
      print STDERR $_ if $self->{debug};
      redo            if /^Devel::Cover: merging run/;
      redo            if /^Set up gcc environment/;    # for MinGW
      if (/Can't opendir\(.+\): No such file or directory/) {
        # parallel tests
        scalar $get_line->();
        redo;
      }
      s/^(Reading database from ).*/$1/;
      s|(__ANON__\[) .* (/tests/ \w+ : \d+ \])|$1$2|x;
      s/(Subroutine) +(Location)/$1 $2/;
      s/-+/-/;
      # s/.* Devel-Cover - \d+ \. \d+ \/*(\S+)\s*/$1/x;
      s/^ \.\.\. .* - \d+ \. \d+ \/*(\S+)\s*/$1/x;
      s/.* Devel \/ Cover \/*(\S+)\s*/$1/x;
      s/^(Devel::Cover: merging run).*/$1/;
      s/^(Run: ).*/$1/;
      s/^(OS: ).*/$1/;
      s/^(Perl version: ).*/$1/;
      s/^(Start: ).*/$1/;
      s/^(Finish: ).*/$1/;
      s/copyright .*//ix;
      no warnings "exiting";
      eval join "; ", @{ $self->{changes} };
      return $_;
    }
  };

  # use Devel::Cover::Dumper; print STDERR "--->", Dumper $self->{changes};
  open my $cover_fh, '-|', "$cover_com 2>&1" or die "Cannot run $cover_com: $!";
  while (!eof $cover_fh) {
    my $t = $change_line->(sub { <$cover_fh> });
    my $c = $change_line->(sub { shift @{ $self->{cover} } });
    # print STDERR "[$t]\n[$c]\n" if $t ne $c;
    do {
      chomp(my $tn = $t);
      chomp(my $cn = $c);
      print STDERR "c-[$tn] $.\ng=[$cn]\n";
    } if $self->{debug};

    if ($self->{differences}) {
      push @at, $t;
      push @ac, $c;
    } else {
      $self->{no_coverage} ? pass : is($t, $c);
      last if $self->{no_coverage} && !@{ $self->{cover} };
    }
  }
  if ($self->{differences}) {
    no warnings "redefine";
    local *Test::_quote = sub { "@_" };
    $self->{no_coverage}
      ? pass
      : eq_or_diff(\@at, \@ac, "output", { context => 0 });
  } elsif ($self->{no_coverage}) {
    pass for @{ $self->{cover} };
  }
  close $cover_fh or die "Cannot close $cover_com: $!";

  1
}

sub create_gold {
  my $self = shift;

  # Pod::Coverage not available on all versions, but it must be there on
  # 5.12.0
  return if $self->{criteria} =~ /\bpod\b/ && $] != 5.012000;

  my ($base, $v) = $self->cover_gold;
  my $gold     = "$base.$v";
  my $new_gold = "$base.$]";
  my $gv       = $v;
  my $ng       = "";

  unless (-e $new_gold) {
    open my $g, ">", $new_gold or die "Can't open $new_gold: $!";
    unlink $new_gold;
  }

  # use Devel::Cover::Dumper; print STDERR Dumper $self;
  if ($self->{skip}) {
    print STDERR "Skipping: $self->{skip}\n";
    return;
  }

  $self->{run_test}
    ? $self->{run_test}->($self)
    : $self->run_command($self->test_command);

  my $cover_com = $self->cover_command;
  print STDERR "Running cover [$cover_com]\n" if $self->{debug};

  open my $gold_fh, ">", $new_gold        or die "Cannot open $new_gold: $!";
  open my $cover_fh, "-|", "$cover_com 2>&1" or die "Cannot run $cover_com: $!";
  while (my $l = <$cover_fh>) {
    next if $l =~ /^Devel::Cover: merging run/;
    $l =~ s/^($_: ).*$/$1.../
      for "Run", "Perl version", "OS", "Start", "Finish";
    $l =~ s/^(Reading database from ).*$/$1.../;
    print STDERR $l if $self->{debug};
    print $gold_fh $l;
    $ng .= $l;
  }
  close $cover_fh or die "Cannot close $cover_com: $!";
  close $gold_fh or die "Cannot close $new_gold: $!";

  print STDERR "gv is $gv and this is $]\n"                if $self->{debug};
  print STDERR "gold is $gold and new_gold is $new_gold\n" if $self->{debug};
  unless ($gv eq "0" || $gv eq $]) {
    open my $gold_fh, $gold or die "Cannot open $gold: $!";
    my $g = do { local $/; <$gold_fh> };
    close $gold_fh or die "Cannot close $gold: $!";

    print STDERR "checking $new_gold against $gold\n" if $self->{debug};
    # print "--[$ng]--\n";
    # print "--[$g]--\n";
    if ($ng eq $g) {
      print STDERR "matches $v";
      unlink $new_gold;
    } else {
      print STDERR "new";
    }
  }

  $self->{end}->() if $self->{end};

  1
}

1

__END__

=head1 NAME

Devel::Cover::Test - Internal module for testing

=head1 METHODS

=cut

=head2 new

  my $test = Devel::Cover::Test->new($test, criteria => $string)

Constructor.

"criteria" parameter (optional, defaults to "statement branch condition
subroutine") is a space separated list of tokens.
Supported tokens are "statement", "branch", "condition", "subroutine" and
"pod".

More optional parameters are supported. Refer to L</get_params> sub.

=head2 shell_quote

  my $quoted_item = shell_quote($item)

Returns properly quoted item to cope with embedded spaces.

=head2 perl

  my $perl = $self->perl

Returns absolute path to Perl interpreter with proper -I options (blib-wise).

=head2 test_command

  my $command = $self->test_command

Returns test command, made of:

=over 4

=item absolute path to Perl interpreter

=item Devel::Cover -M option (if applicable)

=item test file

=item test file parameters (if applicable)

=back

=head2 cover_command

  my $command = $self->cover_command

Returns test command, made of:

=over 4

=item absolute path to Perl interpreter

=item absolute path to cover script

=item cover parameters

=back

=head2 test_file

  my $file = $self->test_file

Returns absolute path to test file.

=head2 test_file_parameters

  my $parameters = $self->test_file_parameters

Accessor to test_file_parameters property.

=head2 get_params

Populates the keys C<criteria>, C<select>, C<test_parameters>, C<db_name>,
C<cover_db>, C<cover_parameters> and C<skip> using the C<test_file> if
available otherwise sets the default.

=head2 cover_gold

  my ($base, $v) = $self->cover_gold;

Returns the absolute path of the base to the golden file and the suffix
version number.

$base comes from the name of the test and $v will be $] from the earliest perl
version for which the golden results should be the same as for the current $]

C<$v> will be overridden if installed libraries' versions dictate; for
instance, if L<Math::BigInt> is at version > 1.999806, then the version
of Perl will be overridden as though it is 5.26.

=head2 run_command

  $self->run_command($command)

Runs command, most likely obtained from L</test_command> sub.

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2001-2025, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

# Copyright 2014, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Collection;

use 5.16.0;
use warnings;

# VERSION

use Devel::Cover::Dumper;

use Capture::Tiny      "capture_merged";
use Parallel::Iterator "iterate_as_array";

use Class::XSAccessor ();
use Moo;
use namespace::clean;
use warnings FATAL => "all";  # be explicit since Moo sets this

my %A = (
    ro  => [ qw( bin_dir cpancover_dir cpanm_dir results_dir force outputfile
                 report timeout verbose workers ) ],
    rwp => [ qw( build_dirs build_dir modules )                         ],
    rw  => [ qw( )                                                      ],
);
while (my ($type, $names) = each %A) { has $_ => (is => $type) for @$names }

sub BUILDARGS {
    my $class = shift;
    my (%args) = @_;
    {
        build_dirs => [],
        cpanm_dir  => glob("~/.cpanm"),
        force      => 0,
        modules    => [],
        outputfile => "index.html",
        report     => "html_basic",
        timeout    => 900,  # fifteen minutes should be enough
        verbose    => 0,
        workers    => 0,
        %args,
    }
};

sub sys {
    my $self = shift;
    my (@command) = @_;
    my $output;
    $output = "-> @command\n" if $self->verbose;
    # TODO - check for failure
    $output .= capture_merged { system @command };
    $output
}

sub initialise {
    my $self = shift;
    my $dir = $self->results_dir // die "No results dir";
    $self->sys("mkdir", "-p", $dir);
}

sub empty_cpanm_dir {
    my $self = shift;
    # TODO - not portable
    my $output = $self->sys("rm", "-rf", $self->cpanm_dir);
    say $output;
}

sub add_modules {
    my $self = shift;
    push @{$self->modules}, @_;
}

sub build_modules {
    my $self = shift;
    my @command = qw( cpanm --notest );
    push @command, "--force" if $self->force;
    for my $module (@{$self->modules}) {
        my $output = $self->sys(@command, $module);
        say $output;
    }
}

sub add_build_dirs {
    my $self = shift;
    push @{$self->build_dirs}, grep -d, glob $self->cpanm_dir . "/work/*/*";
}

sub run {
    my $self = shift;

    my $d = $self->build_dir;
    chdir $d or die "Can't chdir $d: $!\n";

    my $module = $d =~ s|.*/||r;
    say "Checking coverage of $module";
    my $output = "**** Checking coverage of $module ****\n";

    my $db = "$d/cover_db";
    if (-d $db) {
        $output .= "Already analysed\n";
        return unless $self->force;
    }

    $output .= "Testing $module\n";
    # TODO - is ths needed?
    $output .= $self->sys($^X, "Makefile.PL") unless -e "Makefile";

    eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm $self->timeout;
        $ENV{DEVEL_COVER_TEST_OPTS} = "-Mblib=" . $self->bin_dir;
        $output .= $self->sys(
            $^X,                        $ENV{DEVEL_COVER_TEST_OPTS},
            $self->bin_dir . "/cover",  "-test",
            "-report",                  $self->report,
            "-outputfile",              $self->outputfile,
        );
        alarm 0;
    };
    if ($@) {
        die unless $@ eq "alarm\n";   # propagate unexpected errors
        warn "$output\nTimed out after " . $self->timeout . " seconds!\n";
    }

    my $dir = $self->results_dir // die "No results dir";
    $dir .= "/$module";
    $self->sys("mkdir", "-p", $dir);
    $output .= $self->sys("mv", $db, $dir);
    $output .= $self->sys("rm", "-rf", $db);

    my $line = "=" x 80;
    say "\n$line\n$output$line\n";
}

sub run_all {
    my $self = shift;
    # for my $dir (@{$self->build_dirs}) {
        # $self->_set_build_dir($dir);
        # $self->run;
    # }
    # my $workers = $ENV{CPANCOVER_WORKERS} || 0;
    my @res = iterate_as_array
    (
        { workers => $self->workers },
        sub {
            my (undef, $dir) = @_;
            $self->_set_build_dir($dir);
            eval { $self->run };
            warn "\n\n\n[$dir]: $@\n\n\n" if $@;
        },
        $self->build_dirs
    );
    print Dumper \@res;
}

sub generate_html {
    my $self = shift;
}

"
We have normality, I repeat we have normality.
Anything you still can’t cope with is therefore your own problem.
"

__END__

=head1 NAME

Devel::Cover::Collection - Code coverage for a collection of modules

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 OPTIONS

=head1 ENVIRONMENT

=head1 BUGS

Almost certainly.

=head1 LICENCE

Copyright 2014, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available on CPAN and from my
homepage: http://www.pjcj.net/.

=cut

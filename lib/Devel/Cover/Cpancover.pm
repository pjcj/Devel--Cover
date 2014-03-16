# Copyright 2014, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Cpancover;

use 5.16.0;
use warnings;

# VERSION

use Capture::Tiny "capture_merged";

use Class::XSAccessor ();
use Moo;
use namespace::clean;
use warnings FATAL => "all";  # be explicit since Moo sets this

my %A = (
    ro  => [ qw( cpancover_dir cpanm_dir force report timeout verbose ) ],
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
        report     => "html_basic",
        timeout    => 900,  # fifteen minutes should be enough
        verbose    => 0,
        %args,
    }
};

sub sys {
    my $self = shift;
    my (@command) = @_;
    say "-> @command" if $self->verbose;
    my $output = capture_merged { system @command };
    $output
}

sub empty_cpanm_dir {
    my $self = shift;
    # TODO - not portable
    my $output = $self->sys("rm", "-rf", $self->cpanm_dir);
    say $output;
}

sub add_build_dirs {
    my $self = shift;
    push @{$self->build_dirs}, grep -d, glob $self->cpanm_dir . "/work/*/*";
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

sub run_all {
    my $self = shift;
    for my $dir (@{$self->build_dirs}) {
        $self->_set_build_dir($dir);
        $self->sys;
    }
}

sub run {
    my $self = shift;

    my $d = $self->build_dir;
    chdir $d or die "Can't chdir $d: $!\n";

    my $module = $d =~ s|.*/||r;
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
        $output .= $self->sys(
            "cover",       "-test",
            "-report",     $self->report,
            "-outputfile", $self->outputfile,
        );
        alarm 0;
    };
    if ($@) {
        die unless $@ eq "alarm\n";   # propagate unexpected errors
        warn "$output\nTimed out after " . $self->timeout . " seconds!\n";
    }

    say $output;
}

"
We have normality, I repeat we have normality.
Anything you still can’t cope with is therefore your own problem.
"

__END__

=head1 NAME

Devel::Cover::Cpancover - Code coverage for CPAN

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

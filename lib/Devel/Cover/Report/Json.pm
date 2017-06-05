# Copyright 2014-2017, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Report::Json;

use strict;
use warnings;

# VERSION

use Devel::Cover::DB::IO::JSON;
# use Devel::Cover::Dumper;  # For debugging

sub add_runs
{
    my ($db) = @_;
    my @runs;
    for my $r (sort {$a->{start} <=> $b->{start}} $db->runs) {
        push @runs, {
            map { $_ => $r->$_ }
                qw( run perl OS dir name version abstract start finish )
        };
    }
    \@runs
}

sub report
{
    my ($pkg, $db, $options) = @_;

    my %options = map { $_ => 1 } grep !/path|time/, $db->all_criteria, "force";
    $db->calculate_summary(%options);

    my $json = {
        runs    => add_runs($db),
        summary => $db->{summary},
    };
    # print "JSON: ", Dumper $json;
    print "JSON sent to $options->{outputdir}/cover.json\n";

    my $io = Devel::Cover::DB::IO::JSON->new(options => "pretty");
    $io->write($json, "$options->{outputdir}/cover.json");
}

1

__END__

=head1 NAME

Devel::Cover::Report::Json - JSON backend for Devel::Cover

=head1 SYNOPSIS

 cover -report json

=head1 DESCRIPTION

This module provides JSON output for coverage data.
It is designed to be called from the C<cover> program.

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2014-2017, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

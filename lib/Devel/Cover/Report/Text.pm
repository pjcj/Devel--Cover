# Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Report::Text;

use strict;
use warnings;

our $VERSION = "0.16";

use Devel::Cover::DB        0.16;
use Devel::Cover::Statement 0.16;
use Devel::Cover::Branch    0.16;
use Devel::Cover::Condition 0.16;
use Devel::Cover::Pod       0.16;
use Devel::Cover::Time      0.16;

sub print_file
{
    my ($db, $file, $options) = @_;

    my $cover = $db->cover;

    print "$file\n\n";
    my $f = $cover->file($file);

    my $fmt = "%-5s %3s ";
    my @args = ("line", "err");
    my %cr; @cr{$db->criteria} = $db->criteria_short;
    for my $c ($db->criteria)
    {
        if ($options->{show}{$c})
        {
            $fmt .= "%6s ";
            push @args, $cr{$c};
        }
    }

    $fmt .= "  %s\n";
    push @args, "code";

    printf $fmt, @args;

    open F, $file or warn("Unable to open $file: $!\n"), return;

    LINE: while (defined(my $l = <F>))
    {
        chomp $l;
        my $n = $.;

        my %criteria;
        for my $c ($db->criteria)
        {
            next unless $options->{show}{$c};
            my $criterion = $f->$c();
            if ($criterion)
            {
                my $l = $criterion->location($n);
                $criteria{$c} = $l ? [@$l] : $l;
            }
        }

        my $more = 1;
        while ($more)
        {
            my @args = ($n, "");

            my $error = 0;
            $more = 0;
            for my $c ($db->criteria)
            {
                next unless $options->{show}{$c};
                my $o = shift @{$criteria{$c}};
                $more ||= @{$criteria{$c}};
                my $value = $o
                    ? ($c =~ /statement|pod|time/)
                        ? $o->covered
                        : $o->percentage
                    : "";
                push @args, $value;
                $error ||= $o->error if $o;
            }

            $args[1] = "***" if $error;
            push @args, $l;

            # print join(", ", map { "[$_]" } @args), "\n";
            printf $fmt, @args;

            last LINE if $l =~ /^__(END|DATA)__/;
            $n = $l = "";
        }
    }

    close F or die "Unable to close $file: $!";
    print "\n\n";
}

sub print_branches
{
    my ($db, $file, $options) = @_;

    my $cover    = $db->cover;
    my $f        = $cover->file($file);
    my $branches = $f->branch;

    return unless $branches;

    print "Branches\n";
    print "--------\n\n";

    my $tpl = "%-5s %3s %6s %6s %6s   %s\n";
    printf $tpl, "line", "err", "%", "1", "2", "branch";
    printf $tpl, "-----", "---", ("------") x 3, "------";

    for my $location (sort { $a <=> $b } $branches->items)
    {
        my $first = 1;
        for my $b (@{$branches->location($location)})
        {
            printf $tpl,
                   $first ? $location : "", $b->error ? "***" : "",
                   $b->percentage, $b->values, $b->text;
            $first = 0;
        }
    }

    print "\n\n";
}

sub print_conditions
{
    my ($db, $file, $options) = @_;

    my $cover      = $db->cover;
    my $f          = $cover->file($file);
    my $conditions = $f->condition;

    return unless $conditions;

    my $tpl = "%-5s %3s %6s %6s %6s %6s   %s\n";

    my %r;
    for my $location (sort { $a <=> $b } $conditions->items)
    {
        my $first = 1;
        for my $c (@{$conditions->location($location)})
        {
            push @{$r{$c->type}}, sprintf $tpl,
                                          $first ? $location : "",
                                          $c->error ? "***" : "",
                                          $c->percentage, $c->values, $c->text;
            $first = 0;
        }
    }

    my %tt =
    (
        and => [ "!l", "l&&!r", "l&&r"   ],
        or  => [ "l",  "!l&&r", "!l&&!r" ],
    );

    print "Conditions\n";
    print "----------\n\n";

    for my $type (sort keys %r)
    {
        my $tts = $tt{$type} || [ 1, 2, 3 ];
        print "$type conditions\n\n";
        printf $tpl, "line", "err", "%", @$tts, "expr";
        printf $tpl, "-----", "---", ("------") x 4, "----";
        print for @{$r{$type}};
        print "\n";
    }

    print "\n";
}

sub report
{
    my ($pkg, $db, $options) = @_;

    for my $file (@{$options->{file}})
    {
        print_file      ($db, $file, $options);
        print_branches  ($db, $file, $options) if $options->{show}{branch};
        print_conditions($db, $file, $options) if $options->{show}{condition};
    }
}

1

__END__

=head1 NAME

Devel::Cover::Report::Text - Backend for textual reporting of coverage
statistics

=head1 SYNOPSIS

 use Devel::Cover::Report::Text;

 Devel::Cover::Report::Text->report($db, $options);

=head1 DESCRIPTION

This module provides a textual reporting mechanism for coverage data.
It is designed to be called from the C<cover> program.

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 VERSION

Version 0.16 - 9th September 2002

=head1 LICENCE

Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

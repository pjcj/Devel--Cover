# Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::Report::Html;

use strict;
use warnings;

our $VERSION = "0.15";

use Devel::Cover::DB        0.15;
use Devel::Cover::Statement 0.15;
use Devel::Cover::Branch    0.15;
use Devel::Cover::Condition 0.15;
use Devel::Cover::Pod       0.15;
use Devel::Cover::Time      0.15;

use Cwd ();
use Template 2.00;

my $Template;
my %Filenames;
my %File_exists;

sub print_summary
{
    my ($db, $options) = @_;

    my @showing = grep $options->{show}{$_}, $db->all_criteria;
    my @headers = map { ($db->all_criteria_short)[$_] }
                  grep { $options->{show}{($db->all_criteria)[$_]} }
                  (0 .. $db->all_criteria - 1);
    my @files   = (grep($db->{summary}{$_}, @{$options->{file}}), "Total");

    my %vals;

    for my $file (@files)
    {
        my %pvals;
        my $part = $db->{summary}{$file};
        for my $criterion (@showing)
        {
            my $pc = exists $part->{$criterion}
                ? sprintf "%6.2f", $part->{$criterion}{percentage}
                : "n/a";

            my $bg = "";
            if ($pc ne "n/a")
            {
                my $c;
                $c = $pc * 2.55;
                $c = 255 if $c > 255;
                if ($criterion eq "time")
                {
                    $c = 255 - $c;
                    $c = 255 if $file eq "Total";
                }
                $bg = sprintf "#ff%02x00", $c;
            }
            $vals{$file}{$criterion}{pc} = $pc;
            $vals{$file}{$criterion}{bg} = $bg;
        }
    }

    my $vars =
    {
        title       => "Coverage report for $db->{db}",
        showing     => \@showing,
        headers     => \@headers,
        files       => \@files,
        filenames   => \%Filenames,
        file_exists => \%File_exists,
        vals        => \%vals,
    };

    my $html = "$db->{db}/$db->{db}.html";
    $Template->process("html/summary", $vars, $html) or die $Template->error();

    my $cwd = Cwd::cwd();
    print "HTML output sent to $cwd/$html\n";
}

sub print_file
{
    my ($db, $file, $options) = @_;

    my @lines;
    my $cover = $db->cover;
    my @showing = grep $options->{show}{$_}, $db->criteria;
    my @headers = map { ($db->all_criteria_short)[$_] }
                  grep { $options->{show}{($db->criteria)[$_]} }
                  (0 .. $db->criteria - 1);

    my $f = $cover->file($file);

    open F, $file or warn("Unable to open $file: $!\n"), next;
    LINE: while (defined(my $l = <F>))
    {
        my $n = $.;
        chomp $l;

        my %criteria;
        for my $c (@showing)
        {
            my $criterion = $f->$c();
            if ($criterion)
            {
                my $l = $criterion->location($n);
                $criteria{$c} = $l ? [@$l] : $l;
            }
        }

        my $count = 0;
        my $more  = 1;
        while ($more)
        {
            my %line;

            $count++;
            $line{number} = $n;
            $line{text}   = $l;

            my $error = 0;
            $more = 0;
            for my $c (@showing)
            {
                my $o = shift @{$criteria{$c}};
                $more ||= @{$criteria{$c}};
                my $details = $c !~ /statement|pod|time/;
                my $text = $o ? $details ? $o->percentage : $o->covered : "";
                my $bg = $o ? $o->error ? "error" : "ok" : "default";
                my %criterion = ( text => $text, bg => $bg );
                $criterion{link} = "$Filenames{$file}--$c.html#$n-$count"
                    if $details;
                push @{$line{criteria}}, \%criterion;
                $error ||= $o->error if $o;
            }

            $line{bg} = $error ? "error" : "default";

            push @lines, \%line;

            last LINE if $l =~ /^__(END|DATA)__/;
            $n = $l = "";
        }
    }
    close F or die "Unable to close $file: $!";

    my $vars =
    {
        title       => "Coverage report for $file",
        showing     => \@showing,
        headers     => \@headers,
        filenames   => \%Filenames,
        file_exists => \%File_exists,
        lines       => \@lines,
    };

    my $html = "$db->{db}/$Filenames{$file}.html";
    $Template->process("html/file", $vars, $html) or die $Template->error();
}

sub print_branches
{
    my ($db, $file, $options) = @_;

    my @branches;
    my $cover    = $db->cover;
    my $f        = $cover->file($file);
    my $branches = $f->branch;

    return unless $branches;

    for my $location (sort { $a <=> $b } $branches->items)
    {
        my $count = 0;
        for my $b (@{$branches->location($location)})
        {
            $count++;
            push @branches,
                {
                    ref        => "$location-$count",
                    number     => $count == 1 ? $location : "",
                    bg         => $b->error ? "error" : "ok",
                    percentage => $b->percentage,
                    parts      => [ map {text => $_, bg => $_ ? "ok" : "error"},
                                        $b->values ],
                    text       => $b->text,
                };
        }
    }

    my $vars =
    {
        title    => "Branch coverage report for $file",
        branches => \@branches,
    };

    my $html = "$db->{db}/$Filenames{$file}--branch.html";
    $Template->process("html/branches", $vars, $html) or die $Template->error();
}

sub print_conditions
{
    my ($db, $file, $options) = @_;

    my $cover      = $db->cover;
    my $f          = $cover->file($file);
    my $conditions = $f->condition;

    return unless $conditions;

    my %r;
    for my $location (sort { $a <=> $b } $conditions->items)
    {
        my $count = 0;
        for my $c (@{$conditions->location($location)})
        {
            $count++;
            push @{$r{$c->type}},
                {
                    ref        => "$location-$count",
                    number     => $count == 1 ? $location : "",
                    bg         => $c->error ? "error" : "ok",
                    percentage => $c->percentage,
                    parts      => [ map {text => $_, bg => $_ ? "ok" : "error"},
                                        $c->values ],
                    text       => $c->text,
                };
        }
    }

    my %tt =
    (
        and => [ "!l", "l&&!r", "l&&r"   ],
        or  => [ "l",  "!l&&r", "!l&&!r" ],
    );

    my @types = map
        {
            name       => $_,
            headers    => $tt{$_} || [ 1, 2, 3 ],
            conditions => $r{$_},
        }, sort keys %r;

    my $vars =
    {
        title  => "Condition coverage report for $file",
        types  => \@types,
    };

    # use Data::Dumper;
    # print Dumper $vars;

    my $html = "$db->{db}/$Filenames{$file}--condition.html";
    $Template->process("html/conditions", $vars, $html)
        or die $Template->error();
}

sub report
{
    my ($pkg, $db, $options) = @_;

    $Template = Template->new
    ({
        EVAL_PERL    => 0,
        INCLUDE_PATH => [ "./templates" ],
    });

    %Filenames   = map { $_ => do { (my $f = $_) =~ s/\W/-/g; $f } }
                       @{$options->{file}};
    %File_exists = map { $_ => -e } @{$options->{file}};

    print_summary($db, $options);

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

Devel::Cover::Report::Html - Backend for HTML reporting of coverage
statistics

=head1 SYNOPSIS

 use Devel::Cover::Report::Html;

 Devel::Cover::Report::Html->report($db, $options);

=head1 DESCRIPTION

This module provides a HTML reporting mechanism for coverage data.  It
is designed to be called from the C<cover> program.

=head1 SEE ALSO

 Devel::Cover

=head1 BUGS

Huh?

=head1 VERSION

Version 0.15 - 5th September 2002

=head1 LICENCE

Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

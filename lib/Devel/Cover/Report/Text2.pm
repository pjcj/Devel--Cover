package Devel::Cover::Report::Text2;
use strict;
use warnings;

our $VERSION = '0.20';

use Devel::Cover::DB 0.22;
use Devel::Cover::Truth_Table;

my %format = (
	line      => "%4s ",
	err       => "%3s ",
	statement => "%4s ",
	condition => "%-24s ",
	branch    => "%-6s ",
	time      => "%6s ",
	code      => "| %s\n",
);

#-------------------------------------------------------------------------------
# Subroutine : headers()
# Purpose    : Determine field headers for report.
# Notes      :
#-------------------------------------------------------------------------------
sub headers {
	my ($db, $options) = @_;
	my ($fmt, @data);

	for (qw/line err/) {
		$fmt .= $format{$_};
		push @data, $_;
	}

	my %cr;
	@cr{$db->criteria} = $db->criteria_short;
	foreach my $c ($db->criteria) {
		next unless $options->{show}{$c};
		$fmt .= $format{$c};
		push @data, $cr{$c};
	}
	$fmt .= $format{code};
	push @data, 'code';

	return $fmt, @data;
}


#-------------------------------------------------------------------------------
# Subroutine : get_metrics()
# Purpose    : Determine which metrics to include in report.
# Notes      :
#-------------------------------------------------------------------------------
sub get_metrics {
	my ($db, $options, $file_data, $line) = @_;
	my %m;

	for my $c ($db->criteria) {                   # find all metrics available in db
		next unless $options->{show}{$c};         # skip those we don't want in report
		my $criterion = $file_data->$c();         # check if metric collected for this file
		if ($criterion) {                         # if it exists...
			my $li = $criterion->location($line); #   get the metric info for the current line
			$m{$c} = $li ? [@$li] : undef;        #   and stash it
		}
	}
	return %m;
}


#-------------------------------------------------------------------------------
# Subroutine : print_file()
# Purpose    : Print report for file.
# Notes      :
#-------------------------------------------------------------------------------
sub print_file {
	my ($db, $file, $options) = @_;

	open(F, '<', $file) or warn("Unable to open '$file' [$!]\n"), return;

	my $pct  = sprintf("%.1f%%", $db->{summary}{$file}{total}{percentage});
	my $pver = join('.', map {ord} split(//, $^V));
	print <<EOT;
#         File: $file
#     Coverage: $pct
# Perl Version: $pver
#     Platform: $^O

EOT

	my ($fmt, @out) = headers($db, $options);
	printf $fmt, @out;

	my $file_data = $db->cover->file($file);
	while (my $line = <F>) {
		chomp $line;

		my $error;
		my %metric = get_metrics($db, $options, $file_data, $.);
		my @out    = ([$.], ['']);

		foreach my $c ($db->criteria) {
			next unless $options->{show}{$c};
			push(@out, []), next unless $metric{$c};

			my $value = [];
			if ($c eq 'branch') {
				@$value  = $file_data->branch->branch_coverage($.);
				$error ||= $file_data->branch->error($.);
			}
			elsif ($c eq 'condition') {
				@$value  = map {$_->[0]->text} $file_data->condition->truth_table($.);
				$error ||= $file_data->condition->error($.);
			}
			else {
				while (my $o = shift @{$metric{$c}}) {
					push @$value, ($c =~ /statement|pod|time/)
						? $o->covered : $o->percentage;
					$error ||= $o->error;
				}
			}
			push @out, $value;
		}

		$out[1] = ['***'] if $error; # flag missing coverage
		push @out, [$line];

		foreach my $i (0 .. max(map {$#$_} @out)) {
			no warnings 'uninitialized';
			printf $fmt, map{$_->[$i]} @out;
		}

		last if $line =~ /^__(END|DATA)__/;
	}
	close F or die "Unable to close '$file' [$!]";
	print "\n\n";
}


#-------------------------------------------------------------------------------
# Subroutine : max()
# Purpose    : Return the maximum from a list of numbers.
# Notes      :
#-------------------------------------------------------------------------------
sub max {
	my $max = shift;
	foreach (@_) {
		$max = $_ if $_ > $max;
	}
	return $max;
}


#-------------------------------------------------------------------------------
# Subroutine : report()
# Purpose    : Entry point for creating textual reports.
# Notes      :
#-------------------------------------------------------------------------------
sub report {
	my ($pkg, $db, $options) = @_;
	foreach my $file (@{$options->{file}}) {
		print_file($db, $file, $options);
	}
}

1;

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

Version 0.22 - 2nd September 2003

=head1 LICENCE

Copyright 2001-2002, Paul Johnson (pjcj@cpan.org)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut


# Copyright 2004-2012, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# http://www.pjcj.net

package Devel::Cover::DB::Structure;

use strict;
use warnings;

use Carp;
use Digest::MD5;

use Devel::Cover::DB;
use Devel::Cover::DB::IO;
use Devel::Cover::Dumper;

# For comprehensive debug logging.
use constant DEBUG => 0;

# VERSION
our $AUTOLOAD;

sub new
{
    my $class = shift;
    my $self  =
    {
        @_
    };
    bless $self, $class
}

sub DESTROY {}

sub AUTOLOAD
{
    my $self = $_[0];
    my $func = $AUTOLOAD;
    $func =~ s/.*:://;
    my ($function, $criterion) = $func =~ /^(add|get)_(.*)/;
    croak "Undefined subroutine $func called"
        unless $criterion &&
               grep $_ eq $criterion, @Devel::Cover::DB::Criteria,
                                      qw( sub_name file line );
    no strict "refs";
    if ($function eq "get")
    {
        my $c = $criterion eq "time" ? "statement" : $criterion;
        if (grep $_ eq $c, qw( sub_name file line ))
        {
            *$func = sub
            {
                my $self = shift;
                $self->{$c}
            }
        }
        else
        {
            *$func = sub
            {
                my $self   = shift;
                my $digest = shift;
                # print STDERR "file: $digest, condition: $c\n";
                for my $fval (values %{$self->{f}})
                {
                    return $fval->{$c} if $fval->{digest} eq $digest;
                }
                return
            }
        };
    }
    else
    {
        *$func = sub
        {
            my $self = shift;
            my $file = shift;
            push @{$self->{f}{$file}{$criterion}}, @_;
        };
    }
    goto &$func
}

sub debuglog {
    my $self = shift;
    my $dir = "$self->{base}/debuglog";
    unless (mkdir $dir)
    {
        confess "Can't mkdir $dir: $!" unless -d $dir;
    }

    local $\;
    # One log file per process, as we're potentially dumping out large amounts,
    # and might excede the atomic write size of the OS.
    open my $fh, '>>', "$dir/$$" or confess "Can't open $dir/$$: $!";
    print $fh "----------------" . gmtime() . "----------------\n";
    print $fh ref $_ ? Dumper($_) : $_;
    print $fh "\n";
    close $fh or confess "Can't close $dir/$$: $!";
}

sub add_criteria
{
    my $self = shift;
    @{$self->{criteria}}{@_} = ();
    $self
}

sub criteria
{
    my $self = shift;
    keys %{$self->{criteria}}
}

sub set_subroutine
{
    my $self = shift;
    my ($sub_name, $file, $line, $scount) =
       @{$self}{qw( sub_name file line scount )} = @_;

    # When new code is added at runtime, via a string eval in some guise, we
    # need information about where structure information for the subroutine
    # is.  This information is stored in $self->{f}{$file}{start} keyed on the
    # filename, line number, subroutine name and the count, the count being
    # for when there are multiple subroutines of the same name on the same
    # line (such subroutines generally being called BEGIN).

    # print STDERR "set_subroutine start $file:$line $sub_name($scount) ",
                 # Dumper $self->{f}{$file}{start};
    $self->{additional} = 0;
    if ($self->reuse($file))
    {
        # reusing a structure
        if (exists $self->{f}{$file}{start}{$line}{$sub_name}[$scount])
        {
            # sub already exists - normal case
            # print STDERR "reuse $file:$line:$sub_name\n";
            $self->{count}{$_}{$file} =
                $self->{f}{$file}{start}{$line}{$sub_name}[$scount]{$_}
                for $self->criteria;
        }
        else
        {
            # sub doesn't exist, for example a conditional C<eval "use M">
            $self->{additional} = 1;
            if (exists $self->{additional_count}{($self->criteria)[0]}{$file})
            {
                # already had such a sub in module
                # print STDERR "reuse additional $file:$line:$sub_name\n";
                $self->{count}{$_}{$file} =
                    $self->{f}{$file}{start}{$line}{$sub_name}[$scount]{$_} =
                    ($self->add_count($_))[0]
                    for $self->criteria;
            }
            else
            {
                # first such a sub in module
                # print STDERR "reuse first $file:$line:$sub_name\n";
                $self->{count}{$_}{$file} =
                    $self->{additional_count}{$_}{$file} =
                    $self->{f}{$file}{start}{$line}{$sub_name}[$scount]{$_} =
                    $self->{f}{$file}{start}{-1}{"__COVER__"}[$scount]{$_}
                    for $self->criteria;
            }
        }
    }
    else
    {
        # first time sub seen in new structure
        # print STDERR "new $file:$line:$sub_name\n";
        $self->{count}{$_}{$file} =
            $self->{f}{$file}{start}{$line}{$sub_name}[$scount]{$_} =
            $self->get_count($_)
            for $self->criteria;
    }
    # print STDERR "set_subroutine start $file:$line $sub_name($scount) ",
                 # Dumper $self->{f}{$file}{start};
}

sub store_counts
{
    my $self = shift;
    my ($file) = @_;
    $self->{count}{$_}{$file} =
        $self->{f}{$file}{start}{-1}{__COVER__}[0]{$_} =
        $self->get_count($_)
        for $self->criteria;
    # print STDERR Dumper $self->{f}{$file}{start};
}

sub reuse
{
    my $self = shift;
    my ($file) = @_;
    exists $self->{f}{$file}{start}{-1}{"__COVER__"}
    # TODO - exists $self->{f}{$file}{start}{-1}
}

sub set_file
{
    my $self = shift;
    my ($file) = @_;
    $self->{file} = $file;
    my $digest = $self->digest($file);
    if ($digest)
    {
        # print STDERR "Adding $digest for $file\n";
        $self->{f}{$file}{digest} = $digest;
        push @{$self->{digests}{$digest}}, $file;
    }
    $digest
}

sub digest
{
    my $self = shift;
    my ($file) = @_;

    # warn "Opening $file for MD5 digest\n";

    my $digest;
    if (open my $fh, "<", $file)
    {
        binmode $fh;
        $digest = Digest::MD5->new->addfile($fh)->hexdigest;
    }
    else
    {
        print STDERR "Devel::Cover: Warning: can't open $file " .
                                             "for MD5 digest: $!\n"
            unless lc $file eq "-e" or
                      $file =~ $Devel::Cover::DB::Ignore_filenames;
        # require "Cwd"; warn Carp::longmess("in " . Cwd::cwd());
    }
    $digest
}

sub get_count
{
    my $self = shift;
    my ($criterion) = @_;
    return 0 unless $self->{file};  # TODO - how does this get unset?
    $self->{count}{$criterion}{$self->{file}}
}

sub add_count
{
    my $self = shift;
    # warn Carp::longmess("undefined file") unless defined $self->{file};
    return unless defined $self->{file};  # can happen during self_cover
    my ($criterion) = @_;
    $self->{additional_count}{$criterion}{$self->{file}}++
        if $self->{additional};
    ($self->{count}{$criterion}{$self->{file}}++,
     !$self->reuse($self->{file}) || $self->{additional})
}

sub delete_file
{
    my $self = shift;
    my ($file) = @_;
    delete $self->{f}{$file};
}

sub write
{
    my $self = shift;
    my ($dir) = @_;
    # print STDERR Dumper $self;
    $dir .= "/structure";
    unless (mkdir $dir)
    {
        confess "Can't mkdir $dir: $!" unless -d $dir;
    }
    for my $file (sort keys %{$self->{f}})
    {
        $self->{f}{$file}{file} = $file;
        unless ($self->{f}{$file}{digest})
        {
            warn "Can't find digest for $file"
                unless $Devel::Cover::Silent ||
                       $file =~ $Devel::Cover::DB::Ignore_filenames ||
                       ($Devel::Cover::Self_cover &&
                        $file =~ q|/Devel/Cover[./]|);
            next;
        }
        my $df_final = "$dir/$self->{f}{$file}{digest}";
        my $df_temp = "$dir/.$self->{f}{$file}{digest}.$$";
        # TODO - determine if Structure has changed to save writing it.
        # my $f = $df; my $n = 1; $df = $f . "." . $n++ while -e $df;
        # print STDERR "Writing [$file] to [$df]\n";
        my $io = Devel::Cover::DB::IO->new;
        $io->write($self->{f}{$file}, $df_temp); # unless -e $df;
        unless (rename $df_temp, $df_final) {
            unless ($Devel::Cover::Silent) {
                if(-e $df_final) {
                    warn "Can't rename $df_temp to $df_final " .
                           "(which exists): $!";
                    $self->debuglog("Can't rename $df_temp to $df_final " .
                                      "(which exists): $!")
                        if DEBUG;
                } else {
                    warn "Can't rename $df_temp to $df_final: $!";
                    $self->debuglog("Can't rename $df_temp to $df_final: $!")
                        if DEBUG;
                }
            }
            unless (unlink $df_temp) {
                warn "Can't remove $df_temp after failed rename: $!"
                    unless $Devel::Cover::Silent;
                $self->debuglog("Can't remove $df_temp after failed rename: $!")
                    if DEBUG;
            }
        }
    }
}

sub read
{
    my $self     = shift;
    my ($digest) = @_;
    my $file     = "$self->{base}/structure/$digest";
    my $io       = Devel::Cover::DB::IO->new;
    my $s        = eval { $io->read($file) };
    if ($@ or !$s) {
        $self->debuglog("read retrieve $file failed: $@") if DEBUG;
        die $@;
    }
    if (DEBUG) {
        foreach my $key (qw(file digest)) {
            if (!defined $s->{$key}) {
                $self->debuglog("retrieve $file had no $key entry. Got:\n", $s);
            }
        }
    }
    my $d        = $self->digest($s->{file});
    # print STDERR "reading $digest from $file: ", Dumper $s;
    if (!$d) {
        # No digest implies that we can't read the file. Likely this is because
        # it's stored with a relative path. In which case, it's not valid to
        # assume that the file has been changed, and hence that we need to
        # "update" the structure database on disk.
    }
    elsif ($d eq $s->{digest})
    {
        $self->{f}{$s->{file}} = $s;
    }
    else
    {
        warn "Devel::Cover: Deleting old coverage ",
             "for changed file $s->{file}\n";
        if (unlink $file) {
            $self->debuglog("Deleting old coverage $file for changed "
                            . "$s->{file} $s->{digest} vs $d. Got:\n", $s,
                            "Have:\n", $self->{f}{$file})
                if DEBUG;
        } else {
            warn "Devel::Cover: can't delete $file: $!\n";
            $self->debuglog("Failed to delete coverage $file for changed "
                            . "$s->{file} ($!) $s->{digest} vs $d. Got:\n", $s,
                            "Have:\n", $self->{f}{$file})
                if DEBUG;
        }
    }
    $self
}

sub read_all
{
    my ($self) = @_;
    my $dir = $self->{base};
    $dir .= "/structure";
    opendir D, $dir or return;
    for my $d (sort grep $_ !~ /\./, readdir D)
    {
        $self->read($d);
    }
    closedir D or die "Can't closedir $dir: $!";
    $self
}

1

__END__

=head1 NAME

Devel::Cover::DB::Structure - Internal: abstract structure of a source file

=head1 SYNOPSIS

 use Devel::Cover::DB::Structure;

=head1 DESCRIPTION

=head1 SEE ALSO

 Devel::Cover
 Devel::Cover::DB

=head1 METHODS

=head1 BUGS

Huh?

=head1 LICENCE

Copyright 2004-2012, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
http://www.pjcj.net

=cut

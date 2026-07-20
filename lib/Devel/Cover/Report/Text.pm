# Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Report::Text;

use 5.20.0;
use warnings;
use feature qw( postderef say signatures );
no warnings qw( experimental::postderef experimental::signatures );

# VERSION

use Devel::Cover::Criterion ();
use Devel::Cover::Path      qw( common_prefix );

sub _display_mode ($c) {
  Devel::Cover::Criterion->criterion_class($c)->display_mode
}

sub _print_criteria_value ($o, $c) {
  _display_mode($c) eq "count" ? $o->covered : $o->percentage
}

sub _format_value ($o, $c) {
  my $value = _print_criteria_value($o, $c);
  $value = sprintf "%3d", $value if _display_mode($c) eq "percentage";
  $value = "-$value" if $o->uncoverable;
  $value = "*$value" if $o->error;
  $value
}

sub _build_header_format ($db, $options) {
  my $fmt  = "%-5s %3s ";
  my @args = ("line", "err");
  for my $ann ($options->{annotations}->@*) {
    for my $i (0 .. $ann->count - 1) {
      $fmt .= "%-" . $ann->width($i) . "s ";
      push @args, $ann->header($i);
    }
  }
  my %cr;
  @cr{ $db->criteria } = $db->criteria_short;
  for my $c ($db->criteria) {
    next unless $options->{show}{$c};
    $fmt .= "%6s ";
    push @args, $cr{$c};
  }
  $fmt .= "  %s\n";
  push @args, "code";
  ($fmt, @args)
}

sub _criteria_for_line ($f, $db, $options, $n) {
  my %criteria;
  for my $c ($db->criteria) {
    next unless $options->{show}{$c};
    my $criterion = $f->$c();
    if ($criterion) {
      my $l = $criterion->location($n);
      $criteria{$c} = $l ? [@$l] : $l;
    }
  }
  %criteria
}

sub _print_line ($fmt, $db, $options, $file, $n, $l, %criteria) {
  my $more = 1;
  while ($more) {
    my @out   = ($n, "");
    my $error = 0;

    for my $ann ($options->{annotations}->@*) {
      for my $i (0 .. $ann->count - 1) {
        push @out, substr $ann->text($file, $n, $i), 0, $ann->width($i);
        $error ||= $ann->error($file, $n, $i);
      }
    }

    $more = 0;
    for my $c ($db->criteria) {
      next unless $options->{show}{$c};
      my $o   = shift $criteria{$c}->@*;
      $more ||= $criteria{$c}->@*;
      push @out, $o ? _format_value($o, $c) : "";
      $error ||= $o->error if $o;
    }

    $out[1] = "***" if $error;
    push @out, $l;
    printf $fmt, @out;
    $n = $l = "";
  }
}

sub _file_dir ($file) {
  my $dir = $file =~ s|/[^/]+$||r;
  $dir eq $file ? "" : $dir
}

sub print_dir_block ($db, $files, $prefix) {
  return unless @$files > 1;
  my %seen;
  my @dirs = grep !$seen{$_}++, map _file_dir($_), @$files;
  return unless @dirs > 1;

  my @rows;
  for my $dir (@dirs) {
    my $scar = $db->dir_summary($dir, "scar") or return;
    my $display
      = $prefix && $dir =~ /^\Q$prefix\E(.*)/ ? ($1 || ".") : ($dir || ".");
    push @rows, {
        dir      => $display,
        cc       => $scar->{file_cc},
        cov      => sprintf("%.1f", $scar->{file_cov}),
        crap     => sprintf("%.1f", $scar->{file_crap}),
        scar     => sprintf("%.1f", $scar->{file_scar}),
        sort_key => $scar->{file_scar},
      };
  }

  @rows = sort { $b->{sort_key} <=> $a->{sort_key} } @rows;

  my %maxw = (d => 9, cc => 2, cv => 3, cr => 4, s => 4);
  for my $r (@rows) {
    _update_maxw(
      \%maxw,
      d  => $r->{dir},
      cc => $r->{cc},
      cv => $r->{cov},
      cr => $r->{crap},
      s  => $r->{scar},
    );
  }

  say "Directory Summary";
  say "-----------------\n";
  my $tpl = "%-$maxw{d}s %$maxw{cc}s %$maxw{cv}s %$maxw{cr}s %$maxw{s}s\n";
  printf $tpl, "Directory", "CC", "Cov", "CRAP", "SCAR";
  printf $tpl, "-" x $maxw{d}, "-" x $maxw{cc}, "-" x $maxw{cv},
    "-" x $maxw{cr}, "-" x $maxw{s};
  printf $tpl, $_->{dir}, $_->{cc}, $_->{cov}, $_->{crap}, $_->{scar} for @rows;
  say "";
}

sub _print_stat_table ($heading, $headers, $values) {
  my @widths = map {
        length($headers->[$_]) > length($values->[$_])
      ? length $headers->[$_]
      : length $values->[$_]
  } 0 .. $#$headers;
  my $tpl = join(" ", map "%${_}s", @widths) . "\n";

  say $heading;
  say "-" x length($heading), "\n";
  printf $tpl, @$headers;
  printf $tpl, map "-" x $_, @widths;
  printf $tpl, @$values;
  say "";
}

sub print_module_banner ($db, $files) {
  return unless @$files > 1;
  my $scar = $db->summary("Total", "scar");
  return unless $scar && defined $scar->{module_scar};

  _print_stat_table(
    "Module Summary",
    [qw( Files CC Cov CRAP SCAR )],
    [
      scalar @$files,
      $scar->{module_cc},
      sprintf("%.1f", $scar->{module_cov}),
      sprintf("%.1f", $scar->{module_crap}),
      sprintf("%.1f", $scar->{module_scar}),
    ],
  );
  say "";
}

sub _worst_subs_rows ($subs, $display_name, $limit = 3) {
  my @sorted = sort {
         $b->{crap} <=> $a->{crap}
      || $a->{line} <=> $b->{line}
      || $a->{name} cmp $b->{name}
  } @$subs;
  my $top = $#sorted > $limit - 1 ? $limit - 1 : $#sorted;
  map {
    +{
      name => $_->{name},
      cc   => $_->{cc},
      scar => sprintf("%.1f", $_->{scar} // 0),
      loc  => "$display_name:$_->{line}",
    }
  } @sorted[0 .. $top]
}

sub print_file_banner ($db, $file, $short) {
  say "$short->{$file}\n";

  my $scar = $db->summary($file, "scar");
  return unless $scar && defined $scar->{file_scar};

  _print_stat_table(
    "File Summary",
    [qw( CC Cov CRAP SCAR )],
    [
      $scar->{file_cc},
      sprintf("%.1f", $scar->{file_cov}),
      sprintf("%.1f", $scar->{file_crap}),
      sprintf("%.1f", $scar->{file_scar}),
    ],
  );

  my @subs = grep $_->{scar} > 0, ($scar->{subs} || [])->@*;
  return unless @subs;

  my @rows = _worst_subs_rows(\@subs, $short->{$file});
  my %maxw = (n => 10, cc => 2, s => 4, l => 8);
  for my $r (@rows) {
    _update_maxw(
      \%maxw,
      n  => $r->{name},
      cc => $r->{cc},
      s  => $r->{scar},
      l  => $r->{loc},
    );
  }

  say "Worst Subroutines";
  say "-----------------\n";
  my $tpl = "%-$maxw{n}s %$maxw{cc}s %$maxw{s}s  %-$maxw{l}s\n";
  printf $tpl, "Subroutine",   "CC",            "SCAR",         "Location";
  printf $tpl, "-" x $maxw{n}, "-" x $maxw{cc}, "-" x $maxw{s}, "-" x $maxw{l};
  printf $tpl, $_->{name},     $_->{cc},        $_->{scar}, $_->{loc} for @rows;
  say "";
}

sub print_runs ($db, $) {
  for my $r (sort { $a->{start} <=> $b->{start} } $db->runs) {
    say "Run:          ", $r->run;
    say "Perl version: ", $r->perl;
    say "OS:           ", $r->OS;
    say "Start:        ", scalar gmtime $r->start;
    say "Finish:       ", scalar gmtime $r->finish;
    say "";
  }
}

sub print_statement ($db, $file, $options, $short) {
  my $cover = $db->cover;

  my $f = $cover->file($file);

  my ($fmt, @args) = _build_header_format($db, $options);
  printf $fmt, @args;

  my $autoloader = 0;
  open my $fh, "<", $file or warn("Unable to open $file: $!\n"), return;

  while (defined(my $l = <$fh>)) {
    chomp $l;
    my $n = $.;
    $autoloader ||= $l =~ /use\s+AutoLoader/;

    my %criteria = _criteria_for_line($f, $db, $options, $n);
    _print_line($fmt, $db, $options, $file, $n, $l, %criteria);

    last if !$autoloader && $l =~ /^__(END|DATA)__/;
  }

  close $fh or die "Unable to close $file: $!";
  say "\n";
}

sub print_branches ($db, $file, $) {
  my $branches = $db->cover->file($file)->branch;
  return unless $branches;

  say "Branches";
  say "--------\n";

  my $tpl = "%-5s %3s %6s %6s %6s   %s\n";
  printf $tpl, "line", "err", "%", "true", "false", "branch";
  printf $tpl, "-----", "---", ("------") x 3, "------";

  for my $location (sort { $a <=> $b } $branches->items) {
    my $n = 0;
    for my $br ($branches->location($location)->@*) {
      printf $tpl, $n ? "" : $location, $br->error ? "***" : "",
        ($br->uncoverable ? "-" : "") . sprintf("%3d", $br->percentage),
        (map { ($br->uncoverable($_) ? "-" : "") . ($br->covered($_) || 0) }
          0 .. $br->total - 1), $br->text;
      $n++;
    }
  }

  say "\n";
}

sub print_conditions ($db, $file, $) {
  my $conditions = $db->cover->file($file)->condition;
  return unless $conditions;

  my $template = sub ($nh) {
    "%-5s %3s %6s " . ("%6s " x $nh) . "  %s\n"
  };

  my %r;
  for my $location (sort { $a <=> $b } $conditions->items) {
    my %seen;
    for my $c ($conditions->location($location)->@*) {
      push $r{ $c->type }->@*, [$c, $seen{ $c->type }++ ? "" : $location];
    }
  }

  say "Conditions";
  say "----------\n";

  my %seen;
  for my $type (sort keys %r) {
    my $tpl;
    for ($r{$type}->@*) {
      my ($c, $location) = @$_;
      unless ($seen{$type}++) {
        my $headers = $c->headers;
        my $nh      = @$headers;
        $tpl = $template->($nh);
        (my $t = $type) =~ s/_/ /g;
        say "$t conditions\n";
        printf $tpl, "line", "err", "%", @$headers, "expr";
        printf $tpl, "-----", "---", ("------") x ($nh + 1), "----";
      }
      printf $tpl, $location, $c->error ? "***" : "",
        ($c->uncoverable ? "-" : "") . sprintf("%3d", $c->percentage),
        (map { ($c->uncoverable($_) ? "-" : "") . ($c->covered($_) || 0) }
          0 .. $c->total - 1), $c->text;
    }
    say "";
  }

  say "";
}

sub print_mcdc ($db, $file, $) {
  my $mcdc = $db->cover->file($file)->mcdc;
  return unless $mcdc;

  say "MC/DC";
  say "-----\n";

  my @rows;
  for my $location (sort { $a <=> $b } $mcdc->items) {
    my $n = 0;
    for my $m ($mcdc->location($location)->@*) {
      my $missing = $m->unanalysed ? "too many conditions" : join ", ",
        $m->missing->@*;
      push @rows, [$n++ ? "" : $location, $m, $missing];
    }
  }

  my $w = 20;
  for (@rows) { $w = length $_->[2] if length $_->[2] > $w }

  my $tpl = "%-5s %3s %6s %4s %4s   %-${w}s   %s\n";
  printf $tpl, "line",  "err", "%",      "cov",  "tot",  "missing", "expr";
  printf $tpl, "-----", "---", "------", "----", "----", "-" x $w,  "----";

  for my $r (@rows) {
    my ($location, $m, $missing) = @$r;
    printf $tpl, $location, $m->error ? "***" : "",
      ($m->uncoverable ? "-" : "") . sprintf("%3d", $m->percentage),
      $m->covered, $m->total, $missing, $m->text;
  }

  say "\n";
}

sub _update_maxw ($maxw, %vals) {
  for my $k (keys %vals) {
    $maxw->{$k} = length $vals{$k} if length $vals{$k} > $maxw->{$k};
  }
}

sub _gather_subs ($dfile, $pods, $display_name, $scar_lookup) {
  my $subs = $dfile->subroutine or return;
  my %maxw = (h => 8, c => 5, p => 3, s => 10, cc => 3, cr => 5);
  my %by_type;
  my $has_scar = %$scar_lookup;

  for my $location ($subs->items) {
    my $l = $subs->location($location);
    my $d = $pods && $pods->location($location);
    for my $sub (@$l) {
      my $h = "$display_name:$location";
      my $c = ($sub->uncoverable ? "-" : "") . $sub->covered;
      my $e = $pods && shift @$d;
      my $p = $e ? ($e->uncoverable ? "-" : "") . $e->covered : "";
      my $s = $sub->name;

      my $info = $scar_lookup->{"$location\0$s"};
      my $cc   = defined $info ? $info->{cc}                    : "";
      my $cr   = defined $info ? sprintf("%.1f", $info->{scar}) : "";

      _update_maxw(\%maxw, h => $h, c => $c, s => $s, cc => $cc, cr => $cr);
      $maxw{p} = length $p if $p && length $p > $maxw{p};

      my $type = $sub->covered ? "covered" : "uncovered";
      push $by_type{$type}{$s}->@*,
        [$c, $pods ? $p : (), $has_scar ? ($cc, $cr) : (), $h];
    }
  }

  (\%by_type, \%maxw)
}

sub print_subroutines ($db, $file, $options, $short) {
  my $dfile = $db->cover->file($file);
  my $pods  = $options->{show}{pod} && $dfile->pod;
  my $cl    = $db->scar_sub_lookup($file);

  my ($by_type, $maxw) = _gather_subs($dfile, $pods, $short->{$file}, $cl);
  return unless $by_type;

  my $has_scar = %$cl;
  my $tpl      = "%-$maxw->{s}s %$maxw->{c}s ";
  $tpl .= "%$maxw->{p}s "  if $pods;
  $tpl .= "%$maxw->{cc}s " if $has_scar;
  $tpl .= "%$maxw->{cr}s " if $has_scar;
  $tpl .= "%-$maxw->{h}s\n";

  for my $type (sort keys %$by_type) {
    say ucfirst($type),            " Subroutines";
    say "-" x (12 + length $type), "\n";
    printf $tpl, "Subroutine", "Count", $pods ? "Pod" : (),
      $has_scar ? ("CC", "SCAR") : (), "Location";
    printf $tpl, "-" x $maxw->{s}, "-" x $maxw->{c},
      $pods ? "-" x $maxw->{p} : (),
      $has_scar ? ("-" x $maxw->{cc}, "-" x $maxw->{cr}) : (), "-" x $maxw->{h};

    for my $s (sort keys $by_type->{$type}->%*) {
      printf $tpl, $s, @$_
        for sort { $a->[-1] cmp $b->[-1] } $by_type->{$type}{$s}->@*;
    }
    say "";
  }

  say "";
}

sub report ($, $db, $options) {
  my @files = $options->{file}->@*;
  my ($prefix, $short) = common_prefix(@files);

  print_runs($db, $options);
  my @reported_files = grep !$db->cover->file($_)->{meta}{uncompiled}, @files;
  print_module_banner($db, \@reported_files);
  for my $file (@files) {
    next if $db->cover->file($file)->{meta}{uncompiled};
    print_file_banner($db, $file, $short);
    print_statement($db, $file, $options, $short)
      if $options->{show}{statement};
    print_branches($db, $file, $options)   if $options->{show}{branch};
    print_conditions($db, $file, $options) if $options->{show}{condition};
    print_mcdc($db, $file, $options)       if $options->{show}{mcdc};
    print_subroutines($db, $file, $options, $short)
      if $options->{show}{subroutine} || $options->{show}{pod};
  }
  print_dir_block($db, \@reported_files, $prefix);
}

"
Drop the pilot, try my balloon
Drop the monkey, smell my perfume
Drop the mahout, I'm the easy rider
Don't use your army to fight a losing battle
"

__END__

=encoding utf8

=head1 NAME

Devel::Cover::Report::Text - Text backend for Devel::Cover

=head1 SYNOPSIS

 cover -report text

=head1 DESCRIPTION

This module provides a textual reporting mechanism for coverage data. It
produces a plain-text report covering statement, branch, condition, and
subroutine metrics with inline source listing.  When files share a long common
directory prefix, the prefix is stripped and only the distinguishing suffixes
are shown.

It is designed to be called from the C<cover> program.

=head1 SUBROUTINES

=head2 report ($pkg, $db, $options)

Entry point called by the C<cover> tool.  Computes the common directory prefix
across all files, then iterates each file printing whichever sections are
enabled in C<$options>.

=head2 print_runs ($db, $options)

Print metadata for each coverage run: command, Perl version, OS, and
start/finish timestamps.

=head2 print_statement ($db, $file, $options, $short)

Print source lines for C<$file> with per-line coverage counts for each enabled
criterion.  C<$short> is the hashref from L<Devel::Cover::Path/common_prefix>
mapping full paths to display names.

=head2 print_branches ($db, $file, $options)

Print the branch coverage table for C<$file>, showing true/false hit counts and
percentage for each branch point.

=head2 print_conditions ($db, $file, $options)

Print condition coverage tables for C<$file>, grouped by condition type (and,
or, xor).

=head2 print_mcdc ($db, $file, $options)

Print the MC/DC table for C<$file>: per-decision satisfaction percentage,
covered/total atomic counts, the labels of any unsatisfied atomics, and the
decision's source text.

=head2 print_subroutines ($db, $file, $options, $short)

Print covered and uncovered subroutine tables for C<$file>, including call
counts, pod coverage, and source location.

=head1 PRIVATE SUBROUTINES

=head2 _print_criteria_value ($o, $c)

Return the raw coverage value for criterion C<$c> from coverage object C<$o> - a
hit count for statement/sub/pod/time, or a percentage for branch/condition.

=head2 _format_value ($o, $c)

Format a single coverage value, prefixing C<-> for uncoverable and C<*> for
error (uncovered) entries.

=head2 _build_header_format ($db, $options)

Build the C<printf> format string and header row values for the per-line source
listing, incorporating any annotations and enabled criteria.

=head2 _criteria_for_line ($f, $db, $options, $n)

Return a hash of criterion name to coverage data for source line C<$n>, used to
populate one row of the source listing.

=head2 _print_line ($fmt, $db, $options, $file, $n, $l, %criteria)

Print one or more output lines for source line C<$n> with text C<$l>. Multiple
output lines are produced when a single source line has several coverage points
(e.g. chained conditions).

=head2 _update_maxw ($maxw, %vals)

Update column-width hash C<$maxw> in place: for each key in C<%vals>, set
C<< $maxw->{$k} >> to the value's length if it exceeds the current maximum.

=head2 _gather_subs ($dfile, $pods, $display_name, $scar_lookup)

Walk the subroutine and pod coverage data for a file, returning a hashref of
covered/uncovered sub entries and a hashref of column widths for formatting.
When C<$scar_lookup> is non-empty, CC and SCAR values are included in each
entry.

=head1 SEE ALSO

L<Devel::Cover>, L<Devel::Cover::Report::Text2>

=head1 LICENCE

Copyright 2001-2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

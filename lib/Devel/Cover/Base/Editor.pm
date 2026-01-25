# Copyright 2026, Paul Johnson (paul@pjcj.net)

# This software is free.  It is licensed under the same terms as Perl itself.

# The latest version of this software should be available from my homepage:
# https://pjcj.net

package Devel::Cover::Base::Editor;

use 5.20.0;
use warnings;
use feature "signatures";
no warnings "experimental::signatures";

# VERSION

use Template 2.00 ();

sub report ($pkg, $db, $options) {
  my $template = Template->new({
    LOAD_TEMPLATES => [
      Devel::Cover::Base::Editor::Template::Provider->new({
        editor_class => $pkg, })
    ]
  });

  my $vars = {
    runs => [
      map {
        run      => $_->run,
          perl   => $_->perl,
          OS     => $_->OS,
          start  => scalar gmtime $_->start,
          finish => scalar gmtime $_->finish,
      },
      sort { $a->start <=> $b->start } $db->runs,
    ],
    cov_time => do {
      my $time = 0;
      for ($db->runs) {
        $time = $_->finish if $_->finish > $time;
      }
      int $time
    },
    version => $pkg->VERSION,
    files   => $options->{file},
    cover   => $db->cover,
    types   => [ grep $_ ne "time", keys $options->{show}->%* ],
  };

  my $out = "$options->{outputdir}/$options->{outputfile}";
  $template->process($pkg->template_name, $vars, $out) or die $template->error;

  print $pkg->output_message($out) . "\n" unless $options->{silent};
}

sub template_name  { die "Subclass must implement template_name" }
sub templates      { die "Subclass must implement templates" }
sub output_message { die "Subclass must implement output_message" }

1;

package Devel::Cover::Base::Editor::Template::Provider;

use 5.20.0;
use warnings;
use feature "signatures";
no warnings "experimental::signatures";

# VERSION

use parent "Template::Provider";

sub new ($class, $params) {
  my $self = $class->SUPER::new($params);
  $self->{_editor_class} = $params->{editor_class};
  $self
}

sub fetch ($self, $name) {
  my $templates = $self->{_editor_class}->templates;
  $self->SUPER::fetch(exists $templates->{$name} ? \$templates->{$name} : $name)
}

1

__END__

=head1 NAME

Devel::Cover::Base::Editor - Base class for editor coverage report backends

=head1 SYNOPSIS

 package Devel::Cover::Report::MyEditor;
 use parent "Devel::Cover::Base::Editor";

 my %Templates;
 $Templates{myeditor} = <<'EOT';
 ... template content ...
 EOT

 sub template_name   { "myeditor" }
 sub templates       { \%Templates }
 sub output_message ($self, $out) { "MyEditor script written to $out" }

=head1 DESCRIPTION

This is an abstract base class for editor-specific coverage report modules
(Vim, Nvim). It provides the shared C<report()> method that constructs
template variables and processes the editor-specific template.

Subclasses must implement:

=over 4

=item template_name

Returns the template name (e.g., "vim", "nvim").

=item templates

Returns a hashref of template name to template content.

=item output_message

Returns the success message to display (receives output path as argument).

=back

=head1 SEE ALSO

L<Devel::Cover::Report::Vim>, L<Devel::Cover::Report::Nvim>

=head1 LICENCE

Copyright 2026, Paul Johnson (paul@pjcj.net)

This software is free.  It is licensed under the same terms as Perl itself.

The latest version of this software should be available from my homepage:
https://pjcj.net

=cut

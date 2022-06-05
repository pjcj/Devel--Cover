# How to Contribute to Devel::Cover

## Source Code

The source code can be found in the [primary
repository](https://github.com/pjcj/Devel--Cover).  This is also the place to
file bug reports and send pull requests.  There are still some old bug reports
in RT which are described in [a
ticket](https://github.com/pjcj/Devel--Cover/issues/35).

I welcome all contributions, be they in the form of code, bug reports,
suggestions, documentation, discussion or anything else.  In general, and as
with most open source projects, it is wise to discuss any large changes before
starting on implementation.

## How to run Devel::Cover from Git

```sh
cd my_code/
perl -I/path/to/Devel--Cover/lib /path/to/Devel--Cover/bin/cover \
    --test -report html_basic
```

## HTML report generation

Devel::Cover::Web contains a number of static files that are saved when a
report is generated:

- cover.css
- common.js
- css.js
- standardista-table-sorting.js

HTML report formats are:

- html|html_minimal (default)
- html_basic
- html_subtle

They are implemented in:

- Devel::Cover::Report::Html
  - which is an empty subclass of Devel::Cover::Report::Html_minimal
- Devel::Cover::Report::Html_basic
- Devel::Cover::Report::Html_subtle

**Minimal** was written by Michael Carman.  One of the goals was to keep the
output as small as possible and he decided not to use templates.
Unfortunately, minimal does not handle uncovered code correctly and, whilst the
truth tables are nice, they are not always correct when there are many
variables.  This is currently the default HTML report.

**Basic** handles uncovered code correctly and the conditions are displayed
correctly, if not as nicely as in minimal.  It also allows for coloured code.
This report requires [Template Toolkit](https://metacpan.org/pod/Template) and
is the format used for cpancover.

## cpancover

The cpancover project aims to present coverage information for CPAN modules.
The website is found at [cpancover.com](http://cpancover.com/).

Devel::Cover::Collection is used by bin/cpancover and has some templates in it.

In order to run cpancover a few extra modules are needed.  They can be
installed by Running `scripts/dc install_dependencies`.

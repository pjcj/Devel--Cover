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

## Adding tests

The tests found in the CPAN distribution in `t/e2e` are generated from the
files in `tests/`.  Such generating then also needs a file in
`test_output/cover/` to be created using the `create_gold` utility.

Perl internals change between releases and, since Devel::Cover is tightly bound
with at least the perl optree, Devel::Cover output can vary slightly between
perl releases.  For this reason some Devel::Cover tests have different golden
results depending on the perl version.

A set of perl versions can be created by running the `dc all_versions --build`
command.  Once this is done golden results for all versions can be created by
running `make all_gold TEST=circular_ref`.

If you don't have all the perl versions available, and if your new test has the
same results across all versions, golden results can be created by:

```sh
# can set vars just once, obviously
NEWTEST=circular_ref
make gold TEST=$NEWTEST && \
  mv test_output/cover/$NEWTEST.* test_output/cover/$NEWTEST.5.010000 && \
  make test TEST_FILES=t/e2e/a$NEWTEST.t
```

The `e2e` files get generated from `tests` by `perl Makefile.PL`.

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

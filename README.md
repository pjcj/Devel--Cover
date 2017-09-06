# Devel::Cover

## Code coverage metrics for Perl

This module provides code coverage metrics for Perl.  Code coverage metrics
describe how thoroughly tests exercise code.  By using Devel::Cover you can
discover areas of code not exercised by your tests and determine which tests to
create to increase coverage.  Code coverage can be considered an indirect
measure of quality.

Although it is still being developed, Devel::Cover is now quite stable and
provides many of the features to be expected in a useful coverage tool.

Statement, branch, condition, subroutine, and pod coverage information is
reported.  Statement and subroutine coverage data should be accurate.  Branch
and condition coverage data should be mostly accurate too, although not always
what one might initially expect.  Pod coverage comes from Pod::Coverage.  If
Pod::Coverage::CountParents is available it will be used instead.  Coverage
data for other criteria are not yet collected.

The cover program can be used to generate coverage reports.  Devel::Cover ships
with a number of reports including various types of HTML output, textual
reports, a report to display missing coverage in the same format as compilation
errors and a report to display coverage information within the Vim editor.

It is possible to add annotations to reports, for example you can add a column
to an HTML report showing who last changed a line, as determined by git blame.
Some annotation modules are shipped with Devel::Cover and you can easily create
your own.

The gcov2perl program can be used to convert gcov files to "Devel::Cover"
databases.  This allows you to display your C or XS code coverage together with
your Perl coverage, or to use any of the Devel::Cover reports to display your C
coverage data.

Code coverage data are collected by replacing perl ops with functions which
count how many times the ops are executed.  These data are then mapped back to
reality using the B compiler modules.  There is also a statement profiling
facility which should not be relied on.  For proper profiling use
Devel::NYTProf.  Previous versions of Devel::Cover collected coverage data by
replacing perl's runops function.  It is still possible to switch to that mode
of operation, but this now gets little testing and will probably be removed
soon.  You probably don't care about any of this.

The most appropriate mailing list on which to discuss this module would be
perl-qa.  See <http://lists.perl.org/list/perl-qa.html>.

The Devel::Cover repository can be found at
<http://github.com/pjcj/Devel--Cover>.  This is also where problems should be
reported.

To get coverage for an uninstalled module:

    cover -test

or

    cover -delete
    HARNESS_PERL_SWITCHES=-MDevel::Cover make test
    cover

To get coverage for an uninstalled module which uses Module::Build (0.26 or
later):

    ./Build testcover

If the module does not use the t/*.t framework:

    PERL5OPT=-MDevel::Cover make test

If you want to get coverage for a program:

    perl -MDevel::Cover yourprog args
    cover

To alter default values:

    perl -MDevel::Cover=-db,cover_db,-coverage,statement,time yourprog args

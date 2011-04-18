use strict;
use warnings;
use Test::More tests => 1;

# This tests against what is basically a perl bug. When evaluating
# code within a regular expression, the state of the regular
# expression engine may not be altered, i.e. no regex match may be
# performed within a regular expression.
#
# The following code doesn't do that, but entering the eval within the
# regular expression involves a nextstate OP. We hook, among other
# things, into those opcodes, and execute some of our own
# code. Devel::Cover::use_file, to be precise. That function currently
# uses regular expressions, and therefore breaks shit.
#
# We currently avoid calling use_file at all within regexp evals. This
# test makes sure we actually do, and will yell at us if we ever start
# doing it again.
#
# This bug in perl is now fixed with commit 91332126 and part of perl
# 5.13.6. If we ever wanted to use regexp matching from use_file or
# some place, that's called while collecting data, again we could pull
# a hack similar to the aforementioned commit in Cover.xs so we
# continue to work on perls older than 5.13.6.

'x' =~ m{ (?: ((??{ 'x' })) )? }x;

# on debugging perls we'd already have hit an assertion failure
# here. We don't do "pass 'no assertion fail'" tho. I don't know if
# that might mess up $1 for the next test. We also have to use $1
# instead of capturing in a lexical, as that tends to fail rather
# differently.

# on non-debugging perls, the above match tends to succeed, and only
# rarely segfaults. Therefore we also make sure that the result is
# correct. If we hit the bug, it tends to either contain complete
# garbage, (parts of) some random constants from the perl interpreter,
# or segfaults completely when invoking the get magic on it.

is $1, 'x';

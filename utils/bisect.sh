#!/bin/sh -x

make
make
make clean
cp /tmp/accessor /tmp/Accessor_maker.pm tests
cp /tmp/accessor.5.008 test_output/cover
perl Makefile.PL
make
t=t/e2e/aaccessor.t
[ ! -e $t ] && t=t/aaccessor.t
make test TEST_FILES=$t

ret=$?
[ $ret -gt 127 ] && ret=127

rm tests/accessor tests/Accessor_maker.pm test_output/cover/accessor.5.008

# exit $ret

#if you need to invert the exit code, replace the above exit with this:
[ $ret -eq 0 ] && exit 1
exit 0

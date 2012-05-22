make clean
perl Makefile.PL
make
make test TEST_FILES=t/e2e/aaccessor.t


ret=$?
[ $ret -gt 127 ] && ret=127


# exit $ret

#if you need to invert the exit code, replace the above exit with this:
[ $ret -eq 0 ] && exit 1
exit 0

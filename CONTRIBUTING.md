# Adding tests

The tests found in the CPAN distribution in `t/e2e` are generated
from the files in `tests/`. Such generating then also needs a file in
`test_output/cover/` to be created using the `create_gold` utility. One
way to iterate this:

```sh
# can set vars just once, obviously
PERLVER=$(perl -e 'print $]')
NEWTEST=circular_ref
make gold TEST=$NEWTEST && mv test_output/cover/$NEWTEST.$PERLVER test_output/cover/$NEWTEST.5.010000 && make test TEST_FILES=t/e2e/a$NEWTEST.t
```

The `e2e` files get generated from `tests` by `perl Makefile.PL`.

# Devel::Cover Release Process

1. Update Changes
    - Add important changes
    - Credit the author as appropriate
    - Include github and RT numbers

2. Check it in
    - `git commit -m "Add Changes" Changes`

3. Update Contributors

4. Check it in
    - `git commit -m "Update Contributors" Contributors`

5. Update `$Latest_t` in `Makefile.PL`
    - Update test for obsolete development version skipping via
        `$LATEST_RELEASED_PERL` variable in Devel::Cover::Test.pm
    - Update version number in `Makefile.PL`

6. Check it in
    - `git commit -am "Bump version number"`

7. Run basic tests
    - `perl Makefile.PL && make`
    - `make test`

8. Test against all versions
    - `make all_test`

9. Return to base perl version
    - `perl Makefile.PL && make`

10. If there's a new stable release of perl:
    - `dc install_dzil`

11. Make the release
    - `dzil release`
